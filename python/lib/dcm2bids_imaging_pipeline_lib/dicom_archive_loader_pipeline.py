import json
import os
import re
import subprocess
import sys

import lib.exitcode
import lib.utilities
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline

__license__ = "GPLv3"


class DicomArchiveLoaderPipeline(BasePipeline):
    """
    Pipeline that extends the BasePipeline class to add some specific DICOM archive loader processes
    such as dcm2niix conversion, protocol identification and registration into the proper imaging tables.

    Functions that starts with _ are functions specific to the DicomArchiveLoaderPipeline class.
    """

    def __init__(self, loris_getopt_obj, script_name):
        """
        Initiate the DicomArchiveLoaderPipeline class and runs the different steps required to convert the
        DICOM archive into NIfTI files with BIDS associated files and register them into the imaging tables.
        It will run the protocol identification and inserts the NIfTI files into the files tables if the
        protocol was identified. Otherwise, scan will be recorded in mri_protocol_violated_scans or
        mri_violations_log table depending on the violation.

        :param loris_getopt_obj: the LorisGetOpt object with getopt values provided to the pipeline
         :type loris_getopt_obj: LorisGetOpt obj
        :param script_name: name of the script calling this class
         :type script_name: str
        """

        super().__init__(loris_getopt_obj, script_name)
        self.series_uid = self.options_dict["series_uid"]["value"]
        self.tarchive_path = os.path.join(
            self.data_dir, "tarchive", self.dicom_archive_obj.tarchive_info_dict["ArchiveLocation"]
        )
        self.tarchive_id = self.dicom_archive_obj.tarchive_info_dict["TarchiveID"]

        # ---------------------------------------------------------------------------------------------
        # Run the DICOM archive validation script to check if the DICOM archive is valid
        # ---------------------------------------------------------------------------------------------
        self._run_dicom_archive_validation_pipeline()

        # ---------------------------------------------------------------------------------------------
        # Extract DICOM files from the tarchive
        # ---------------------------------------------------------------------------------------------
        self.extracted_dicom_dir = self.imaging_obj.extract_files_from_dicom_archive(
            os.path.join(self.data_dir, 'tarchive', self.dicom_archive_obj.tarchive_info_dict["ArchiveLocation"]),
            self.tmp_dir
        )

        # ---------------------------------------------------------------------------------------------
        # Run dcm2niix to generate the NIfTI files with a JSON file storing imaging parameters
        # ---------------------------------------------------------------------------------------------
        self.nifti_tmp_dir = self._run_dcm2niix_conversion()

        # ---------------------------------------------------------------------------------------------
        # Get the list of NIfTI files to run through NIfTI insertion pipeline
        # ---------------------------------------------------------------------------------------------
        self.excluded_series_desc_regex_list = self.config_db_obj.get_config("excluded_series_description")
        self.nifti_files_to_insert = self._get_nifti_files_to_insert()
        self.file_to_insert_count = len(self.nifti_files_to_insert) + 1
        if self.file_to_insert_count < 1:
            message = "No data could be converted into valid NIfTI files."
            if type(self.excluded_series_desc_regex_list) is str:
                message += f"{self.excluded_series_desc_regex_list} will not be considered!"
            else:
                message += f"{', '.join(self.excluded_series_desc_regex_list)} will not be considered!"
            self.log_error_and_exit(message, lib.exitcode.NO_VALID_NIfTI_CREATED, is_error="Y", is_verbose="N")
        else:
            message = f"Number of NIfTI files that will be considered for insertion into the database: " \
                      f"{self.file_to_insert_count}"
            self.log_info(message, is_error="N", is_verbose="Y")

        # ---------------------------------------------------------------------------------------------
        # Loop through NIfTI files and call run_nifti_insertion.pl
        # ---------------------------------------------------------------------------------------------
        self.inserted_file_count = 0
        self._loop_through_nifti_files_and_insert()

        # ---------------------------------------------------------------------------------------------
        # If at least one file inserted, move DICOM archive into year subfolder
        # ---------------------------------------------------------------------------------------------
        if self.inserted_file_count > 0:
            self._move_and_update_dicom_archive()
            self._compute_snr()
            self._add_intended_for_to_fieldmap_json_files()
            self._order_modalities_per_acquisition_type()
            self._update_mri_upload()

        self._get_summary_of_insertion()
        self.remove_tmp_dir()  # remove temporary directory
        sys.exit(lib.exitcode.SUCCESS)

    def _run_dicom_archive_validation_pipeline(self):
        """
        Runs the script `run_dicom_archive_validation.py` to ensure the DICOM archive to process is valid.
        Once the script is done running, check in the database that the mri_upload table was properly updated.
        If not, self.check_if_tarchive_validated_in_db() will exit and log the error in the notification spool
        table and log files.
        """

        validation_command = [
            "run_dicom_archive_validation.py",
            "-p", self.options_dict["profile"]["value"],
            "-t", self.tarchive_path,
            "-u", str(self.upload_id)
        ]
        if self.verbose:
            validation_command.append("-v")

        validation_process = subprocess.Popen(validation_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        validation_process.communicate()
        if validation_process.returncode == 0:
            message = f"run_dicom_archive_validation.py successfully executed for UploadID {self.upload_id} " \
                      f"and ArchiveLocation {self.tarchive_path}"
            self.log_info(message, is_error="N", is_verbose="Y")
        else:
            message = f"run_dicom_archive_validation.py failed validation for UploadID {self.upload_id}" \
                      f"and ArchiveLocation {self.tarchive_path}. Exit code was {validation_process.returncode}."
            self.log_error_and_exit(message, lib.exitcode.INVALID_DICOM, is_error="Y", is_verbose="N")

        # now that the DICOM archive validation has run, check the database to ensure the validation was completed
        # and correctly updated in the DB
        self.check_if_tarchive_validated_in_db()

    def _run_dcm2niix_conversion(self):
        """
        Run the conversion to NIfTI files with JSON side car files that store scan parameters.
        The converter is run with the following options:
            - `-ba n`  => generate the BIDS compatible JSON side car which will contain PII information such as
                          dates, SeriesUID and PatientName (previously deidentified to PSCID_CandID_Visit)
            - `-z y`   => generate a GZIP NIfTI file to save disk space

        :return: path to the directory with the generated NIfTI and associated files (JSON, bval, bvec)
         :rtype: str
        """

        nifti_tmp_dir = os.path.join(self.tmp_dir, "nifti_files")
        os.makedirs(nifti_tmp_dir)

        converter = self.config_db_obj.get_config("converter")
        if not re.search('.*dcm2niix.*', converter, re.IGNORECASE):
            message = f"{converter} does not appear to be a dcm2niix binary."
            self.log_error_and_exit(message, lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE, is_error="Y", is_verbose="N")

        dcm2niix_process = subprocess.Popen(
            [converter, "-ba", "n", "-z", "y", "-o", nifti_tmp_dir, self.extracted_dicom_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT
        )
        stdout, stderr = dcm2niix_process.communicate()
        self.log_info(stdout, is_error="N", is_verbose="Y")

        return nifti_tmp_dir

    def _get_nifti_files_to_insert(self):
        """
        Read the tmp directory with NIfTI files and gather all NIfTI and side car file information into a list
        of dictionary of the following form:
        [
            {
                "nifti_file": <path to the NIfTI file in the tmp directory>,
                "json_file": <path to the JSON file in the tmp directory>,
                "bval_file": <path to the BVAL file in the tmp directory>,
                "bvec_file": <path to the BVEC file in the tmp directory>
            },
            {
                "nifti_file": <path to the NIfTI file in the tmp directory>,
                "json_file": <path to the JSON file in the tmp directory>,
                "bval_file": <path to the BVAL file in the tmp directory>,
                "bvec_file": <path to the BVEC file in the tmp directory>
            },
            ...
        ]

        :return: list of dictionary with path to files to insert along with NIfTI files that should be considered
                 for insertion. Note: the list will be ordered by series_number.
         :rtype: list
        """

        # get the list of NIfTI files created by the dcm2niix command
        nifti_files_list = [f for f in os.listdir(self.nifti_tmp_dir) if f.endswith(".nii.gz")]

        # organize the files created by dcm2niix as a list of dictionaries with paths to the NIfTI,
        # JSON, BVAL and BVEC files if found on the filesystem for a given NIfTI file
        nifti_files_to_insert_list = []
        for nifti_filename in nifti_files_list:
            nifti_file_path = os.path.join(self.nifti_tmp_dir, nifti_filename)
            json_file_path = nifti_file_path.replace(".nii.gz", ".json")
            bval_file_path = nifti_file_path.replace(".nii.gz", ".bval")
            bvec_file_path = nifti_file_path.replace(".nii.gz", ".bvec")

            # skip if JSON file does not exist or series description should be excluded from insertion
            if not os.path.isfile(json_file_path) or self._is_series_description_to_be_excluded(json_file_path):
                continue

            with open(json_file_path) as json_file:
                json_data_dict = json.load(json_file)

            nifti_file_dict = {
                "nifti_file": nifti_file_path,
                "json_file": json_file_path,
                "SeriesNumber": json_data_dict["SeriesNumber"]
            }
            if os.path.exists(bval_file_path):
                nifti_file_dict["bval_file"] = bval_file_path
            if os.path.exists(bvec_file_path):
                nifti_file_dict["bvec_file"] = bvec_file_path

            nifti_files_to_insert_list.append(nifti_file_dict)

        # sort list of nifti files per series number
        sorted_nifti_files_to_insert_list = sorted(nifti_files_to_insert_list, key=lambda x: x["SeriesNumber"])

        return sorted_nifti_files_to_insert_list

    def _is_series_description_to_be_excluded(self, json_file_path):
        """
        Function that checks whether the Series Description stored in a JSON file matches one of the
        regex of series description to exclude from insertion to the files table.

        :param json_file_path: path to the JSON file to read to grep the series description info
         :type json_file_path: str

        :return: True if the series description matches one of the regex stored in the Config module, False otherwise
         :rtype: bool
        """

        # get the series description from the JSON file
        with open(json_file_path) as json_file:
            json_data_dict = json.load(json_file)

        if "SeriesDescription" not in json_data_dict.keys():
            return False

        series_desc = json_data_dict["SeriesDescription"]

        if type(self.excluded_series_desc_regex_list) is str:
            pattern = re.compile(self.excluded_series_desc_regex_list, re.IGNORECASE)
            return True if re.search(pattern, series_desc) else False
        else:
            for regex in self.excluded_series_desc_regex_list:
                pattern = re.compile(regex, re.IGNORECASE)
                if re.search(pattern, series_desc):
                    return True

    def _loop_through_nifti_files_and_insert(self):
        """
        Loop through the list of NIfTI files to process through run_nifti_insertion.py for insertion
        into the imaging tables of the database.
        """

        for file_dict in self.nifti_files_to_insert:
            nifti_file_path = file_dict["nifti_file"]
            json_file_path = file_dict["json_file"]
            if "bval_file" in file_dict.keys() and "bvec_file" in file_dict.keys():
                bval_file_path = file_dict["bval_file"]
                bvec_file_path = file_dict["bvec_file"]
                self._run_nifti_insertion(nifti_file_path, json_file_path, bval_file_path, bvec_file_path)
            else:
                self._run_nifti_insertion(nifti_file_path, json_file_path)

    def _run_nifti_insertion(self, nifti_file_path, json_file_path, bval_file_path=None, bvec_file_path=None):
        """
        Executes `run_nifti_insertion.py` on the NIfTI file to process.

        :param nifti_file_path: path of the NIfTI file to insert
         :type nifti_file_path: str
        :param json_file_path: path to the side car JSON file
         :type json_file_path: str
        :param bval_file_path: path to the bval file associated to the NIfTI file if there is any
         :type bval_file_path: str
        :param bvec_file_path: path to the bvec file associated to the NIfTI file if there is any
         :type bvec_file_path: str
        """

        nifti_insertion_command = [
            "run_nifti_insertion.py",
            "-p", self.options_dict["profile"]["value"],
            "-u", str(self.upload_id),
            "-n", nifti_file_path,
            "-j", json_file_path,
            "-c"
        ]
        if bval_file_path:
            nifti_insertion_command.extend(["-l", bval_file_path])
        if bvec_file_path:
            nifti_insertion_command.extend(["-e", bvec_file_path])
        if self.verbose:
            nifti_insertion_command.append("-v")

        insertion_process = subprocess.Popen(nifti_insertion_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        stdout, stderr = insertion_process.communicate()

        if insertion_process.returncode == 0:
            message = f"run_nifti_insertion.py successfully executed for file {nifti_file_path}"
            self.log_info(message, is_error="N", is_verbose="Y")
            self.inserted_file_count += 1
        else:
            message = f"run_nifti_insertion.py failed for file {nifti_file_path}.\n{stdout}"
            print(stdout)
            self.log_info(message, is_error="Y", is_verbose="Y")

    def _move_and_update_dicom_archive(self):
        """
        Moves the DICOM archive into a year subfolder (if a date is available for the DICOM archive) and update
        the `tarchive` table with the new `ArchiveLocation` and `SessionID`.
        """

        tarchive_id = self.tarchive_id
        acq_date = self.dicom_archive_obj.tarchive_info_dict["DateAcquired"]
        archive_location = self.dicom_archive_obj.tarchive_info_dict["ArchiveLocation"]

        fields_to_update = ("SessionID",)
        values_for_update = (self.session_obj.session_id,)
        pattern = re.compile("^[0-9]{4}/")
        if acq_date and not pattern.match(archive_location):
            # move the DICOM archive into a year subfolder
            year_subfolder = acq_date.strftime("%Y")
            new_archive_location = os.path.join(year_subfolder, archive_location)
            destination_dir_path = os.path.join(self.data_dir, "tarchive", year_subfolder)
            new_tarchive_path = os.path.join(destination_dir_path, archive_location)
            if not os.path.exists(destination_dir_path):
                # create the year subfolder is it does not exist yet on the filesystem
                os.makedirs(destination_dir_path)
            os.replace(self.tarchive_path, new_tarchive_path)
            self.tarchive_path = new_tarchive_path
            # add the new archive location to the list of fields to update in the tarchive table
            fields_to_update += ("ArchiveLocation",)
            values_for_update += (new_archive_location,)

        self.dicom_archive_obj.tarchive_db_obj.update_tarchive(tarchive_id, fields_to_update, values_for_update)

    def _compute_snr(self):
        # TODO: to be implemented later on. No clear paths as to how to compute that
        pass

    def _add_intended_for_to_fieldmap_json_files(self):
        """
        Add IntendedFor field in JSON file of fieldmap acquisitions according to BIDS standard for fieldmaps.
        """

        fmap_files_dict = self.imaging_obj.determine_intended_for_field_for_fmap_json_files(self.tarchive_id)

        for key in fmap_files_dict.keys():
            sorted_fmap_files_list = fmap_files_dict[key]
            self.imaging_obj.modify_fmap_json_file_to_write_intended_for(sorted_fmap_files_list)

    def _order_modalities_per_acquisition_type(self):
        """
        Determine the file order based on the modality and populated the `files` table field `AcqOrderPerModality`.
        """

        tarchive_id = self.tarchive_id
        scan_type_id_list = self.imaging_obj.files_db_obj.select_distinct_acquisition_protocol_id_per_tarchive_source(
            tarchive_id
        )
        for scan_type_id in scan_type_id_list:
            results = self.imaging_obj.files_db_obj.get_file_ids_and_series_number_per_scan_type_and_tarchive_id(
                tarchive_id, scan_type_id
            )
            file_id_series_nb_ordered_list = sorted(results, key=lambda x: x["SeriesNumber"])
            acq_number = 0
            for item in file_id_series_nb_ordered_list:
                file_id = item["FileID"]
                acq_number += 1
                self.imaging_obj.files_db_obj.update_files(file_id, ("AcqOrderPerModality",), (acq_number,))

    def _update_mri_upload(self):
        """
        Update the `mri_upload` table with summary of processing. The following fields will be updated:
            - `Inserting`              => 0 (since the processing on that upload is finished)
            - `InsertionComplete`      => 1 (since the insertion has been completed)
            - `number_of_mincInserted` => total number of NIfTI files found in the `files` table for the `TarchiveID`
                                          associated to the upload
            - `number_of_mincCreated`  => number of NIfTI files created by dcm2niix to consider for insertion
            - `SessionID`              => `SessionID` associated to the upload
        """

        files_inserted_list = self.imaging_obj.files_db_obj.get_files_inserted_for_tarchive_id(self.tarchive_id)
        self.imaging_upload_obj.update_mri_upload(
            upload_id=self.upload_id,
            fields=("Inserting", "InsertionComplete", "number_of_mincInserted", "number_of_mincCreated", "SessionID"),
            values=("0", "1", len(files_inserted_list), len(self.nifti_files_to_insert), self.session_obj.session_id)
        )

    def _get_summary_of_insertion(self):
        """
        Generate a summary of the DICOM archive loader pipeline execution. That summary will include the following
        information:
            - DICOM archive info (`TarchiveID` and DICOM archive path)
            - number of files inserted into the files table
            - number of files inserted into the mri_protocol_violated_scans table
            - number of files inserted into the mri_violations_log with Severity=exclude
            - path to the log file
        """

        files_results = self.imaging_obj.files_db_obj.get_files_inserted_for_tarchive_id(self.tarchive_id)
        files_inserted_list = [v["File"] for v in files_results] if files_results else None
        prot_viol_results = self.imaging_obj.mri_prot_viol_scan_db_obj.get_protocol_violations_for_tarchive_id(
            self.tarchive_id
        )
        protocol_violations_list = [v["minc_location"] for v in prot_viol_results] if prot_viol_results else None
        excl_viol_results = self.imaging_obj.mri_viol_log_db_obj.get_excluded_violations_for_tarchive_id(
            self.tarchive_id, "exclude"
        )
        excluded_violations_list = [v["MincFile"] for v in excl_viol_results] if excl_viol_results else None

        nb_files_inserted = len(files_inserted_list) if files_inserted_list else 0
        nb_prot_violation = len(protocol_violations_list) if protocol_violations_list else 0
        nb_excluded_viol = len(excluded_violations_list) if excluded_violations_list else 0

        files_list = ', '.join(files_inserted_list) if files_inserted_list else 0
        prot_viol_list = ', '.join(protocol_violations_list) if protocol_violations_list else 0
        excl_viol_list = ', '.join(excluded_violations_list) if excluded_violations_list else 0

        summary = f"""
        Finished processing UploadID {self.upload_id}!
        - DICOM archive info: {self.tarchive_id} => {self.tarchive_path}
        - {nb_files_inserted} files were inserted into the files table: {files_list}
        - {nb_prot_violation} files did not match any protocol: {prot_viol_list}
        - {nb_excluded_viol} files were exclusionary violations: {excl_viol_list}
        - Log of process in {self.log_obj.log_file}
        """
        self.log_info(summary, is_error="N", is_verbose="Y")

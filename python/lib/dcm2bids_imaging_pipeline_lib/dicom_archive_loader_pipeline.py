import json
import os
import re
import subprocess
import tarfile

import lib.exitcode
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline

__license__ = "GPLv3"


class DicomArchiveLoaderPipeline(BasePipeline):

    def __init__(self, loris_getopt_obj, script_name):
        super().__init__(loris_getopt_obj, script_name)
        self.series_uid = self.options_dict["series_uid"]["value"]
        self.tarchive_path = os.path.join(
            self.data_dir, "tarchive", self.dicom_archive_obj.tarchive_info_dict["ArchiveLocation"]
        )
        # ---------------------------------------------------------------------------------------------
        # Run the DICOM archive validation script to check if the DICOM archive is valid
        # ---------------------------------------------------------------------------------------------
        self._run_dicom_archive_validation_pipeline()

        # ---------------------------------------------------------------------------------------------
        # Extract DICOM files from the tarchive
        # ---------------------------------------------------------------------------------------------
        self.extracted_dicom_dir = self._extract_dicom_files()

        # ---------------------------------------------------------------------------------------------
        # Run dcm2niix
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
            self._move_and_update_dicom_archive()  # TODO implement functions below
            self._compute_snr()
            self._order_modalities_per_acquisition_type()
            self._update_mri_upload()

        self._send_out_summary_of_insertion()

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
        stdout, stderr = validation_process.communicate()
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

    def _extract_dicom_files(self):
        tarchive_path = os.path.join(
            self.data_dir,
            'tarchive',
            self.dicom_archive_obj.tarchive_info_dict["ArchiveLocation"]
        )
        tar = tarfile.open(tarchive_path)
        tar.extractall(path=self.tmp_dir)
        inner_tar_file_name = [f.name for f in tar.getmembers() if f.name.endswith('.tar.gz')][0]
        tar.close()

        inner_tar_path = os.path.join(self.tmp_dir, inner_tar_file_name)
        inner_tar = tarfile.open(inner_tar_path)
        inner_tar.extractall(path=self.tmp_dir)
        inner_tar.close()

        dicom_dir = inner_tar_path.replace(".tar.gz", "")
        return dicom_dir

    def _run_dcm2niix_conversion(self):

        nifti_tmp_dir = os.path.join(self.tmp_dir, "nifti_files")
        os.makedirs(nifti_tmp_dir)

        dcm2niix_process = subprocess.Popen(
            ["dcm2niix", "-ba", "n", "-z", "y", "-o", nifti_tmp_dir, self.extracted_dicom_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT
        )
        stdout, stderr = dcm2niix_process.communicate()
        if self.verbose:
            print(stdout)

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
        for insertion
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

            if self._is_series_description_to_be_excluded(json_file_path):
                continue

            nifti_file_dict = {
                "nifti_file": nifti_file_path,
                "json_file": json_file_path
            }
            if os.path.exists(bval_file_path):
                nifti_file_dict["bval_file"] = bval_file_path
            if os.path.exists(bvec_file_path):
                nifti_file_dict["bvec_file"] = bvec_file_path

            nifti_files_to_insert_list.append(nifti_file_dict)

        return nifti_files_to_insert_list

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
        series_desc = json_data_dict["SeriesDescription"]

        if type(self.excluded_series_desc_regex_list) is str:
            pattern = re.compile(self.excluded_series_desc_regex_list)
            return True if pattern.match(series_desc) else False
        else:
            for regex in self.excluded_series_desc_regex_list:
                pattern = re.compile(regex)
                if pattern.match(series_desc):
                    return True

    def _loop_through_nifti_files_and_insert(self):

        for file_dict in self.nifti_files_to_insert:
            nifti_file_path = file_dict["nifti_file"]
            json_file_path = file_dict["json_file"]
            if "bval" in file_dict.keys() and "bvec" in file_dict.keys():
                bval_file_path = file_dict["bval_file"]
                bvec_file_path = file_dict["bvec_file"]
                self._run_nifti_insertion(nifti_file_path, json_file_path, bval_file_path, bvec_file_path)
            else:
                self._run_nifti_insertion(nifti_file_path, json_file_path)

    def _run_nifti_insertion(self, nifti_file_path, json_file_path, bval_file_path=None, bvec_file_path=None):

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
            nifti_insertion_command.append(f"-v")

        print(nifti_insertion_command)

        insertion_process = subprocess.Popen(nifti_insertion_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        stdout, stderr = insertion_process.communicate()

        print(insertion_process.returncode)
        print(stdout)

        if insertion_process.returncode == 0:
            self.inserted_file_count += 1

    def _move_and_update_dicom_archive(self):
        # TODO: move dicom archive if needed, update ArchiveLocation and SessionID
        pass

    def _compute_snr(self):
        pass

    def _order_modalities_per_acquisition_type(self):
        pass

    def _update_mri_upload(self):
        # TODO: update number of files created and inserted as well as SessionID field
        pass

    def _send_out_summary_of_insertion(self):
        # TODO: figure out how to log files moved to trashbin (done by NIfTI insertion script directly)
        #     - can get that info from violations_log and mri_protocol_violated_scans
        pass

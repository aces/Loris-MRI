import datetime
import getpass
import json
import os
import re
import subprocess
import sys

import lib.exitcode
import lib.utilities as utilities
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline
from lib.exception.determine_subject_info_error import DetermineSubjectInfoError
from lib.exception.validate_subject_info_error import ValidateSubjectInfoError
from lib.get_subject_session import get_subject_session
from lib.logging import log_error_exit, log_verbose
from lib.validate_subject_info import validate_subject_info

__license__ = "GPLv3"


class NiftiInsertionPipeline(BasePipeline):
    """
    Pipeline that extends the BasePipeline class to add some specific NIfTI insertion processes
    such as protocol identification and registration into the proper imaging tables.

    Functions that starts with _ are functions specific to the NiftiInsertionPipeline class.
    """

    def __init__(self, loris_getopt_obj, script_name):
        """
        Initiate the NiftiInsertionPipeline class and runs the different steps required to insert a
        NIfTI file with BIDS associated files into the imaging tables.
        It will run the protocol identification and inserts the NIfTI file into the files tables if the
        protocol was identified. Otherwise, scan will be recorded in mri_protocol_violated_scans or
        mri_violations_log table depending on the violation.

        :param loris_getopt_obj: the LorisGetOpt object with getopt values provided to the pipeline
         :type loris_getopt_obj: LorisGetOpt obj
        :param script_name: name of the script calling this class
         :type script_name: str
        """
        super().__init__(loris_getopt_obj, script_name)
        self.nifti_path = self.options_dict["nifti_path"]["value"]
        self.nifti_s3_url = self.options_dict["nifti_path"]["s3_url"] \
            if 's3_url' in self.options_dict["nifti_path"].keys() else None
        self.nifti_blake2 = utilities.compute_blake2b_hash(self.nifti_path)
        self.nifti_md5 = utilities.compute_md5_hash(self.nifti_path)
        self.json_path = self.options_dict["json_path"]["value"]
        self.json_blake2 = utilities.compute_blake2b_hash(self.json_path) if self.json_path else None
        self.bval_path = self.options_dict["bval_path"]["value"]
        self.bval_blake2 = utilities.compute_blake2b_hash(self.bval_path) if self.bval_path else None
        self.bvec_path = self.options_dict["bvec_path"]["value"]
        self.bvec_blake2 = utilities.compute_blake2b_hash(self.bvec_path) if self.bval_path else None
        self.json_md5 = utilities.compute_md5_hash(self.json_path)
        self.loris_scan_type = self.options_dict["loris_scan_type"]["value"]
        self.bypass_extra_checks = self.options_dict["bypass_extra_checks"]["value"]

        # ---------------------------------------------------------------------------------------------
        # Set 'Inserting' flag to 1 in mri_upload
        # ---------------------------------------------------------------------------------------------
        self.imaging_upload_obj.update_mri_upload(upload_id=self.upload_id, fields=('Inserting',), values=('1',))

        # ---------------------------------------------------------------------------------------------
        # Get S3 object from loris_getopt object
        # ---------------------------------------------------------------------------------------------
        self.s3_obj = self.loris_getopt_obj.s3_obj

        # ---------------------------------------------------------------------------------------------
        # Check the mri_upload table to see if the DICOM archive has been validated
        # ---------------------------------------------------------------------------------------------
        self.check_if_tarchive_validated_in_db()

        # ---------------------------------------------------------------------------------------------
        # Load the JSON file object with scan parameters if a JSON file was provided
        # ---------------------------------------------------------------------------------------------
        self.json_file_dict = self._load_json_sidecar_file()
        self._add_step_and_space_params_to_json_file_dict()

        # ---------------------------------------------------------------------------------------------
        # Check that the PatientName in NIfTI and DICOMs are the same and then validate the Subject IDs
        # ---------------------------------------------------------------------------------------------
        if self.dicom_archive_obj.tarchive_info_dict.keys():
            self._validate_nifti_patient_name_with_dicom_patient_name()
            self.subject_info = self.imaging_obj.determine_subject_info(
                self.dicom_archive_obj.tarchive_info_dict, self.scanner_id
            )
        else:
            self._determine_subject_info_based_on_json_patient_name()

        try:
            validate_subject_info(self.env.db, self.subject_info)
        except ValidateSubjectInfoError as error:
            self.imaging_obj.insert_mri_candidate_errors(
                self.dicom_archive_obj.tarchive_info_dict['PatientName'],
                self.dicom_archive_obj.tarchive_info_dict['TarchiveID'],
                self.json_file_dict,
                self.nifti_path,
                error.message,
            )

            if self.nifti_s3_url:  # push candidate errors to S3 if provided file was on S3
                self._run_push_to_s3_pipeline()

            log_error_exit(self.env, error.message, lib.exitcode.CANDIDATE_MISMATCH)

        # ---------------------------------------------------------------------------------------------
        # Verify if the image/NIfTI file was not already registered into the database
        # ---------------------------------------------------------------------------------------------
        self._check_if_nifti_file_was_already_inserted()

        # ---------------------------------------------------------------------------------------------
        # Determine/create the session the file should be linked to
        # ---------------------------------------------------------------------------------------------
        self.session = get_subject_session(self.env, self.subject_info)

        # ---------------------------------------------------------------------------------------------
        # Determine acquisition protocol (or register into mri_protocol_violated_scans and exits)
        # ---------------------------------------------------------------------------------------------
        self.scan_type_id, self.mri_protocol_group_id = self._determine_acquisition_protocol()
        if not self.loris_scan_type:
            if not self.scan_type_id:
                self._move_to_trashbin()
                self._register_protocol_violated_scan()
                if self.nifti_s3_url:  # push violations to S3 if provided file was on S3
                    self._run_push_to_s3_pipeline()
                log_error_exit(
                    self.env,
                    f"{self.nifti_path}'s acquisition protocol is 'unknown'.",
                    lib.exitcode.UNKNOWN_PROTOCOL,
                )
            else:
                self.loris_scan_type = self.imaging_obj.get_scan_type_name_from_id(self.scan_type_id)
        else:
            self.scan_type_id = self.imaging_obj.get_scan_type_id_from_scan_type_name(self.loris_scan_type)
            if not self.scan_type_id:
                self._move_to_trashbin()
                self._register_protocol_violated_scan()
                if self.nifti_s3_url:  # push violations to S3 if provided file was on S3
                    self._run_push_to_s3_pipeline()
                log_error_exit(
                    self.env,
                    (
                        f"{self.nifti_path}'s scan type {self.loris_scan_type} provided to run_nifti_insertion.py"
                        f" is not a valid scan type in the database."
                    ),
                    lib.exitcode.UNKNOWN_PROTOCOL,
                )

        # ---------------------------------------------------------------------------------------------
        # Determine BIDS scan type info based on scan_type_id
        # ---------------------------------------------------------------------------------------------
        self.bids_categories_dict = self.imaging_obj.get_bids_categories_mapping_for_scan_type_id(self.scan_type_id)
        if not self.bids_categories_dict:
            self._move_to_trashbin()
            self._register_protocol_violated_scan()
            if self.nifti_s3_url:  # push violations to S3 if provided file was on S3
                self._run_push_to_s3_pipeline()
            log_error_exit(
                self.env,
                f"Scan type {self.loris_scan_type} does not have BIDS tables set up.",
                lib.exitcode.UNKNOWN_PROTOCOL,
            )

        # ---------------------------------------------------------------------------------------------
        # Run extra file checks to determine possible protocol violations
        # ---------------------------------------------------------------------------------------------
        self.warning_violations_list = []
        self.exclude_violations_list = []
        if not self.bypass_extra_checks:
            self.violations_summary = self.imaging_obj.run_extra_file_checks(
                self.session.project_id,
                self.session.cohort_id,
                self.session.visit_label,
                self.scan_type_id,
                self.json_file_dict
            )
            self.warning_violations_list = self.violations_summary['warning']
            self.exclude_violations_list = self.violations_summary['exclude']

        # ---------------------------------------------------------------------------------------------
        # Register files in the proper tables
        # ---------------------------------------------------------------------------------------------
        if self.exclude_violations_list:
            self._move_to_trashbin()
            self._register_violations_log(self.exclude_violations_list, self.trashbin_nifti_rel_path)
            self._register_violations_log(self.warning_violations_list, self.trashbin_nifti_rel_path)
            if self.nifti_s3_url:  # push violations to S3 if provided file was on S3
                self._run_push_to_s3_pipeline()
            log_error_exit(
                self.env,
                (
                    f"{self.nifti_path} violates exclusionary checks listed in mri_protocol_checks. "
                    f"  List of violations are: {self.exclude_violations_list}"
                ),
                lib.exitcode.UNKNOWN_PROTOCOL,
            )
        else:
            self._move_to_assembly_and_insert_file_info()

        # ---------------------------------------------------------------------------------------------
        # Create the pic images
        # ---------------------------------------------------------------------------------------------
        self._create_pic_image()

        # ---------------------------------------------------------------------------------------------
        # Remove the tmp directory from the file system
        # ---------------------------------------------------------------------------------------------
        self.remove_tmp_dir()

        # ---------------------------------------------------------------------------------------------
        # Push inserted images to S3 if they were downloaded from S3
        # ---------------------------------------------------------------------------------------------
        if self.nifti_s3_url:
            self._run_push_to_s3_pipeline()

        # ---------------------------------------------------------------------------------------------
        # If we get there, the insertion was complete and successful
        # ---------------------------------------------------------------------------------------------
        self.imaging_upload_obj.update_mri_upload(upload_id=self.upload_id, fields=('Inserting',), values=('0',))
        sys.exit(lib.exitcode.SUCCESS)

    def _load_json_sidecar_file(self):
        """
        Loads the JSON file content into a dictionary.

        Note: if no JSON file was provided to the pipeline, the function will return an empty dictionary so that
         information to be stored in <parameter_file> will be added to the JSON dictionary later on.

        :return: dictionary with the information present in the JSON file
         :rtype: dict
        """
        json_path = self.options_dict["json_path"]["value"]

        if not json_path:
            return dict()

        with open(json_path) as json_file:
            json_data_dict = json.load(json_file)

        return json_data_dict

    def _validate_nifti_patient_name_with_dicom_patient_name(self):
        """
        This function will validate that the PatientName present in the JSON side car file is the same as the
        one present in the <tarchive> table.

        Note: if no JSON file was provided to the script or if no "PatientName" was provided in the JSON file,
        the scripts will rely solely on the PatientName present in the <tarchive> table.
        """
        tarchive_pname = self.dicom_archive_obj.tarchive_info_dict["PatientName"]
        if "PatientName" not in self.json_file_dict:
            log_verbose(self.env, (
                "PatientName not present in the JSON file or no JSON file provided along with"
                "the NIfTI file. Will rely on the PatientName stored in the DICOM files"
            ))

            return

        nifti_pname = self.json_file_dict["PatientName"]
        if tarchive_pname != nifti_pname:
            err_msg = "PatientName in DICOM and NIfTI files differ."
            self.imaging_obj.insert_mri_candidate_errors(
                nifti_pname,
                self.dicom_archive_obj.tarchive_info_dict["TarchiveID"],
                self.json_file_dict,
                self.nifti_path,
                err_msg
            )

            log_error_exit(self.env, err_msg, lib.exitcode.FILENAME_MISMATCH)

    def _check_if_nifti_file_was_already_inserted(self):
        """
        Ensures that the NIfTI file was not already inserted. It checks whether there is already a file inserted into
        the files table with the same SeriesUID/EchoTime, as well as whether there is a file inserted with the same
        md5 or blake2b hash.

        Proper information will be logged into the log file, notification table and terminal.
        """

        error_msg = None
        json_keys = self.json_file_dict.keys()
        if self.json_file_dict and "SeriesInstanceUID" in json_keys and "EchoTime" in json_keys:
            # verify that a file has not already be inserted with the same SeriesUID/EchoTime combination if
            # SeriesInstanceUID and EchoTime have been set in the JSON side car file
            echo_time = self.json_file_dict["EchoTime"]
            series_uid = self.json_file_dict["SeriesInstanceUID"]
            echo_nb = self.json_file_dict["EchoNumber"] if "EchoNumber" in json_keys else None
            phase_enc_dir = self.json_file_dict["PhaseEncodingDirection"] \
                if "PhaseEncodingDirection" in json_keys else None
            match = self.imaging_obj.grep_file_info_from_series_uid_and_echo_time(
                series_uid, echo_time, phase_enc_dir, echo_nb
            )
            if match:
                error_msg = f"There is already a file registered in the files table with SeriesUID {series_uid}," \
                            f" EchoTime {echo_time}, EchoNumber {echo_nb} and PhaseEncodingDirection {phase_enc_dir}." \
                            f" The already registered file is {match['File']}"

            # If force option has been used, check that there is no matching SeriesUID/EchoTime entry in tarchive_series
            if self.force:
                tar_echo_time = echo_time * 1000
                self.dicom_archive_obj.populate_tarchive_info_dict_from_series_uid_and_echo_time(
                    series_uid, tar_echo_time
                )
                if not self.dicom_archive_obj.tarchive_info_dict:
                    error_msg = f"Found a DICOM archive containing DICOM files with the same SeriesUID ({series_uid})" \
                                f" and EchoTime ({tar_echo_time}) as the one present in the JSON side car file. " \
                                f" The DICOM archive location containing those DICOM files is " \
                                f" {self.dicom_archive_obj.tarchive_info_dict['ArchiveLocation']}. Please, rerun " \
                                f" <run_nifti_insertion.py> with either --upload_id or --tarchive_path option."

        # verify that a file with the same MD5 or blake2b hash has not already been inserted
        md5_match = self.imaging_obj.grep_file_info_from_hash(self.nifti_md5)
        blake2b_match = self.imaging_obj.grep_file_info_from_hash(self.nifti_blake2)
        if md5_match:
            error_msg = f"There is already a file registered in the files table with MD5 hash {self.nifti_md5}." \
                        f" The already registered file is {md5_match['File']}"
        elif blake2b_match:
            error_msg = f"There is already a file registered in the files table with Blake2b hash {self.nifti_blake2}."\
                        f" The already registered file is {blake2b_match['File']}"

        if error_msg:
            log_error_exit(self.env, error_msg, lib.exitcode.FILE_NOT_UNIQUE)

    def _determine_subject_info_based_on_json_patient_name(self):
        """
        Determines the subject IDs information based on the patient name information present in the JSON file.
        """

        dicom_header = self.config_db_obj.get_config('lookupCenterNameUsing')
        dicom_value = self.json_file_dict[dicom_header]

        try:
            self.subject_info = self.imaging_obj.determine_subject_info(dicom_value)
        except DetermineSubjectInfoError as error:
            log_error_exit(self.env, error.message, lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE)

        log_verbose(self.env, "Determined subject IDs based on PatientName stored in JSON file")

    def _determine_acquisition_protocol(self):
        """
        Determines the acquisition protocol of the NIfTI file.

        :return: identified acquisition protocol ID for the NIfTI file
         :rtype: int
        """

        nifti_name = os.path.basename(self.nifti_path)
        scan_param = self.json_file_dict

        # get scanner ID if not already figured out
        if not self.scanner_id:
            self.scanner_id = self.imaging_obj.get_scanner_id(
                self.json_file_dict['Manufacturer'],
                self.json_file_dict['SoftwareVersions'],
                self.json_file_dict['DeviceSerialNumber'],
                self.json_file_dict['ManufacturersModelName'],
                self.site_dict['CenterID'],
                self.session.project_id,
            )

        # get the list of lines in the mri_protocol table that apply to the given scan based on the protocol group
        protocols_list = self.imaging_obj.get_list_of_eligible_protocols_based_on_session_info(
            self.session.project_id,
            self.session.cohort_id,
            self.session.site_id,
            self.session.visit_label,
            self.scanner_id
        )

        protocol_info = self.imaging_obj.get_acquisition_protocol_info(
            protocols_list, nifti_name, scan_param, self.loris_scan_type
        )

        log_verbose(self.env, protocol_info['error_message'])

        return protocol_info['scan_type_id'], protocol_info['mri_protocol_group_id']

    def _add_step_and_space_params_to_json_file_dict(self):
        """
        Adds step and space information to the JSON file dictionary listing NIfTI file acquisition parameters.
        """
        step_params = self.imaging_obj.get_nifti_image_step_parameters(self.nifti_path)
        length_params = self.imaging_obj.get_nifti_image_length_parameters(self.nifti_path)
        self.json_file_dict['xstep'] = step_params[0]
        self.json_file_dict['ystep'] = step_params[1]
        self.json_file_dict['zstep'] = step_params[2]
        self.json_file_dict['xspace'] = length_params[0]
        self.json_file_dict['yspace'] = length_params[1]
        self.json_file_dict['zspace'] = length_params[2]
        self.json_file_dict['time'] = length_params[3] if len(length_params) == 4 else None

    def _move_to_assembly_and_insert_file_info(self):
        """
        Determines where the NIfTI file and its associated files (.json, .bval, .bvec...) will go in the assembly_bids
        directory, move the files and inserts the NIfTI file information into the files/parameter_file tables.
        If the image has 'warning' violations the violations will be inserted into the mri_violations_table as
        well and the Caveat will be set to True in the files table.
        """

        # add TaskName to the JSON file if the file's BIDS scan type subcategory contains task-*
        bids_subcategories = self.bids_categories_dict['BIDSScanTypeSubCategory']
        if self.json_path and bids_subcategories and re.match(r'task-', bids_subcategories):
            with open(self.json_path) as json_file:
                json_data = json.load(json_file)
            json_data['TaskName'] = re.search(r'task-([a-zA-Z0-9]*)', bids_subcategories).group(1)
            with open(self.json_path, 'w') as json_file:
                json_file.write(json.dumps(json_data, indent=4))

        # determine the new file paths and move the files in assembly_bids
        self.assembly_nifti_rel_path = self._determine_new_nifti_assembly_rel_path()
        self._create_destination_dir_and_move_image_files('assembly_bids')

        # register the files in the database (files and parameter_file tables)
        self.file_id = self._register_into_files_and_parameter_file(self.assembly_nifti_rel_path)
        log_verbose(
            self.env,
            f"Registered file {self.assembly_nifti_rel_path} into the files table with FileID {self.file_id}"
        )

        # add an entry in the violations log table if there is a warning violation associated to the file
        if self.warning_violations_list:
            log_verbose(self.env, (
                f"Inserting warning violations related to {self.assembly_nifti_rel_path}."
                f"  List of violations found: {self.warning_violations_list}"
            ))

            self._register_violations_log(self.warning_violations_list, self.assembly_nifti_rel_path)

    def _determine_new_nifti_assembly_rel_path(self):
        """
        Determines the directory and the new NIfTI name of the file that will be moved into the assembly folder.

        :return: relative path to the new NIfTI file
         :rtype: str
        """

        # determine file BIDS entity values for the file into a dictionary
        file_bids_entities_dict = {
            'sub': self.subject_info.cand_id,
            'ses': self.subject_info.visit_label,
            'run': 1
        }
        if self.bids_categories_dict['BIDSEchoNumber']:
            file_bids_entities_dict['echo'] = self.bids_categories_dict['BIDSEchoNumber']
        if self.bids_categories_dict['BIDSScanTypeSubCategory']:
            subcategories_list = self.bids_categories_dict['BIDSScanTypeSubCategory'].split('_')
            for subcategory in subcategories_list:
                key, value = subcategory.split('-')
                file_bids_entities_dict[key] = value

        # determine where the file should go
        bids_cand_id = 'sub-' + str(self.subject_info.cand_id)
        bids_visit = 'ses-' + self.subject_info.visit_label
        bids_subfolder = self.bids_categories_dict['BIDSCategoryName']

        # determine NIfTI file name
        new_nifti_name = self._construct_nifti_filename(file_bids_entities_dict)
        already_inserted_filenames = self.imaging_obj.get_list_of_files_already_inserted_for_session_id(
            self.session.id,
        )
        while new_nifti_name in already_inserted_filenames:
            file_bids_entities_dict['run'] += 1
            new_nifti_name = self._construct_nifti_filename(file_bids_entities_dict)

        return os.path.join('assembly_bids', bids_cand_id, bids_visit, bids_subfolder, new_nifti_name)

    def _construct_nifti_filename(self, file_bids_entities_dict):
        """
        Determines the name of the NIfTI file according to what is present in the bids_mri_scan_type_rel table.

        :param file_bids_entities_dict: dictionary with the BIDS entities grepped from the bids_mri_scan_type_rel table
         :type file_bids_entities_dict: str

        :return: name of the NIfTI to be inserted
         :rtype: str
        """

        # this list defined the order in which BIDS entities should appear in the filename
        bids_entity_order = (
            'sub',       # Subject
            'ses',       # Session
            'task',      # Task
            'acq',       # Acquisition
            'ce',        # Contrast Enhancing Agent
            'rec',       # Reconstruction
            'dir',       # Phase Encoding Direction
            'run',       # Run
            'mod',       # Corresponding Modality
            'echo',      # Echo
            'flip',      # Flip Angle
            'inv',       # Inversion Time
            'mt',        # Magnetization Transfer
            'part',      # Part
            'recording'  # Recording
        )

        nifti_filename = ''
        for entity in bids_entity_order:
            if entity == 'sub':
                nifti_filename += f"{entity}-{file_bids_entities_dict[entity]}"
            elif entity == "echo" and self.bids_categories_dict['BIDSScanType'] == 'magnitude':
                self.bids_categories_dict['BIDSScanType'] = f"magnitude{file_bids_entities_dict[entity]}"
            else:
                if entity in file_bids_entities_dict.keys():
                    nifti_filename += f"_{entity}-{file_bids_entities_dict[entity]}"

        # add BIDS scan type to the NIfTI filename
        nifti_filename += f"_{self.bids_categories_dict['BIDSScanType']}"

        # determine NIfTI file extension and append it to filename
        curr_nifti_path = self.nifti_path
        nifti_ext = re.search(r"\.nii(\.gz)?$", curr_nifti_path).group()
        nifti_filename += nifti_ext

        return nifti_filename

    def _move_to_trashbin(self):
        """
        Determines where the NIfTI file will go under the trashbin directory and move the file there.
        """
        self.trashbin_nifti_rel_path = os.path.join(
            'trashbin',
            re.sub(r'\.log', '', os.path.basename(self.env.log_file)),
            os.path.basename(self.nifti_path)
        )
        self._create_destination_dir_and_move_image_files('trashbin')

    def _create_destination_dir_and_move_image_files(self, destination):
        """
        Create the destination directory for the files and move the NIfTI file and its associated files there.

        :param destination: destination root directory (one of 'assembly_bids' or 'trashbin')
         :type destination: str
        """
        nii_rel_path = self.assembly_nifti_rel_path if destination == 'assembly_bids' else self.trashbin_nifti_rel_path
        json_rel_path = re.sub(r"\.nii(\.gz)?$", '.json', nii_rel_path) if self.json_path else None
        bval_rel_path = re.sub(r"\.nii(\.gz)?$", '.bval', nii_rel_path) if self.bval_path else None
        bvec_rel_path = re.sub(r"\.nii(\.gz)?$", '.bvec', nii_rel_path) if self.bvec_path else None

        absolute_dir_path = os.path.join(self.data_dir, os.path.dirname(nii_rel_path))
        self.create_dir(absolute_dir_path)

        file_type_to_move_list = [
            {
                'original_file_path': self.nifti_path,
                'new_file_path': os.path.join(self.data_dir, nii_rel_path)
            }
        ]
        if self.json_path:
            file_type_to_move_list.append(
                {
                    'original_file_path': self.json_path,
                    'new_file_path': os.path.join(self.data_dir, json_rel_path)
                }
            )
        if self.bval_path:
            file_type_to_move_list.append(
                {
                    'original_file_path': self.bval_path,
                    'new_file_path': os.path.join(self.data_dir, bval_rel_path)
                }
            )
        if self.bvec_path:
            file_type_to_move_list.append(
                {
                    'original_file_path': self.bvec_path,
                    'new_file_path': os.path.join(self.data_dir, bvec_rel_path)
                }
            )

        for file_dict in file_type_to_move_list:
            original_file_path = file_dict['original_file_path']
            new_file_path = file_dict['new_file_path']

            log_verbose(self.env, f"Moving file {original_file_path} to {new_file_path}")

            self.move_file(original_file_path, new_file_path)

        if destination == 'assembly_bids':
            self.json_file_dict['file_blake2b_hash'] = self.nifti_blake2
            if self.json_path:
                self.json_file_dict['bids_json_file'] = json_rel_path
                self.json_file_dict['bids_json_file_blake2b_hash'] = self.json_blake2
            if self.bval_path:
                self.json_file_dict['check_bval_filename'] = bval_rel_path
                self.json_file_dict['check_bval_filename_blake2b_hash'] = self.bval_blake2
            if self.bvec_path:
                self.json_file_dict['check_bvec_filename'] = bvec_rel_path
                self.json_file_dict['check_bvec_filename_blake2b_hash'] = self.bvec_blake2

    def _register_protocol_violated_scan(self):
        """
        Register a file with unknown protocol into mri_protocol_violated_scans.
        """

        patient_name = None
        if "PatientName" in self.json_file_dict.keys():
            patient_name = self.json_file_dict["PatientName"]
        elif "PatientName" in self.dicom_archive_obj.tarchive_info_dict.keys():
            patient_name = self.dicom_archive_obj.tarchive_info_dict["PatientName"]

        self.imaging_obj.insert_protocol_violated_scan(
            patient_name,
            self.subject_info.cand_id,
            self.subject_info.psc_id,
            self.dicom_archive_obj.tarchive_info_dict['TarchiveID'],
            self.json_file_dict,
            self.trashbin_nifti_rel_path,
            self.mri_protocol_group_id
        )

    def _register_mri_candidate_errors(self):

        patient_name = None
        if "PatientName" in self.json_file_dict.keys():
            patient_name = self.json_file_dict["PatientName"]
        elif "PatientName" in self.dicom_archive_obj.tarchive_info_dict.keys():
            patient_name = self.dicom_archive_obj.tarchive_info_dict["PatientName"]

        self.imaging_obj.insert_mri_candidate_errors(
            patient_name
        )

    def _register_violations_log(self, violations_list, file_rel_path):
        """
        Register the list of violations into the mri_violations_log table (one row per violation
        listed in violations_list).

        :param violations_list: list of violations to be inserted into mri_violations_log
         :type violations_list: list
        :param file_rel_path: file relative path (in assembly_bids or trashbin depending on the violation's severity)
         :type file_rel_path: str
        """
        scan_param = self.json_file_dict
        phase_enc_dir = scan_param['PhaseEncodingDirection'] if 'PhaseEncodingDirection' in scan_param.keys() else None
        base_info_dict = {
            'TimeRun': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'SeriesUID': scan_param['SeriesInstanceUID'] if 'SeriesInstanceUID' in scan_param.keys() else None,
            'TarchiveID': self.dicom_archive_obj.tarchive_info_dict['TarchiveID'],
            'MincFile': file_rel_path,
            'PatientName': self.subject_info.name,
            'CandID': self.subject_info.cand_id,
            'Visit_label': self.subject_info.visit_label,
            'MriScanTypeID': self.scan_type_id,
            'EchoTime': scan_param['EchoTime'] if 'EchoTime' in scan_param.keys() else None,
            'EchoNumber': scan_param['EchoNumber'] if 'EchoNumber' in scan_param.keys() else None,
            'PhaseEncodingDirection': phase_enc_dir,
            'MriProtocolChecksGroupID': self.mri_protocol_group_id
        }
        for violation_dict in violations_list:
            info_to_insert_dict = base_info_dict | violation_dict
            self.imaging_obj.insert_mri_violations_log(info_to_insert_dict)

    def _register_into_files_and_parameter_file(self, nifti_rel_path):
        """
        Registers the image into files and file_parameter via the lib.imaging library.

        :param nifti_rel_path: relative path to the imaging file to use for the File column of the files table
         :type nifti_rel_path: str

        :return: file ID of the inserted image
         :rtype: int
        """

        scan_param = self.json_file_dict
        acquisition_date = None
        phase_enc_dir = scan_param['PhaseEncodingDirection'] if 'PhaseEncodingDirection' in scan_param.keys() else None
        if "AcquisitionDateTime" in scan_param.keys():
            acquisition_date = datetime.datetime.strptime(
                scan_param['AcquisitionDateTime'], '%Y-%m-%dT%H:%M:%S.%f'
            ).strftime("%Y-%m-%d")
        file_type = self.imaging_obj.determine_file_type(nifti_rel_path)
        if not file_type:
            log_error_exit(
                self.env,
                f"Could not determine file type for {nifti_rel_path}. No entry found in ImagingFileTypes table",
                lib.exitcode.SELECT_FAILURE,
            )

        files_insert_info_dict = {
            'SessionID': self.session.id,
            'File': nifti_rel_path,
            'SeriesUID': scan_param['SeriesInstanceUID'] if 'SeriesInstanceUID' in scan_param.keys() else None,
            'EchoTime': scan_param['EchoTime'] if 'EchoTime' in scan_param.keys() else None,
            'EchoNumber': scan_param['EchoNumber'] if 'EchoNumber' in scan_param.keys() else None,
            'PhaseEncodingDirection': phase_enc_dir,
            'CoordinateSpace': 'native',
            'OutputType': 'native',
            'MriScanTypeID': self.scan_type_id,
            'FileType': file_type,
            'InsertedByUserID': getpass.getuser(),
            'InsertTime': datetime.datetime.now().timestamp(),
            'Caveat': 1 if self.warning_violations_list else 0,
            'TarchiveSource': self.dicom_archive_obj.tarchive_info_dict['TarchiveID'],
            'ScannerID': self.scanner_id,
            'AcquisitionDate': acquisition_date,
            'SourceFileID': None
        }
        file_id = self.imaging_obj.insert_imaging_file(files_insert_info_dict, self.json_file_dict)

        return file_id

    def _create_pic_image(self):
        """
        Creates the pic image of the NIfTI file.
        """
        file_info = {
            'cand_id': self.subject_info.cand_id,
            'data_dir_path': self.data_dir,
            'file_rel_path': self.assembly_nifti_rel_path,
            'is_4D_dataset': True if self.json_file_dict['time'] else False,
            'file_id': self.file_id
        }
        pic_rel_path = self.imaging_obj.create_imaging_pic(file_info)

        self.imaging_obj.insert_parameter_file(self.file_id, 'check_pic_filename', pic_rel_path)

    def _run_push_to_s3_pipeline(self):
        """
        Run push to S3 script to upload data to S3. This function is called only when the file path to insert provided
        to the script is an S3 URL.
        """

        push_to_s3_cmd = [
            "run_push_imaging_files_to_s3_pipeline.py",
            "-p", self.options_dict["profile"]["value"],
            "-u", str(self.upload_id),
        ]
        if self.verbose:
            push_to_s3_cmd.append("-v")

        s3_process = subprocess.Popen(push_to_s3_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        stdout, _ = s3_process.communicate()

        if s3_process.returncode == 0:
            log_verbose(
                self.env,
                f"run_push_imaging_files_to_s3_pipeline.py successfully executed for Upload ID {self.upload_id}"
            )
        else:
            log_verbose(
                self.env,
                f"run_push_imaging_files_to_s3_pipeline.py failed for Upload ID {self.upload_id}.\n{stdout}"
            )

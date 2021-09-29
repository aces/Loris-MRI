import datetime
import getpass
import hashlib
import json
import lib.exitcode
import os
import re
from lib.database_lib.mri_protocol_violated_scans import MriProtocolViolatedScans
from lib.database_lib.mri_scan_type import MriScanType
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline
from pyblake2 import blake2b

__license__ = "GPLv3"


class NiftiInsertionPipeline(BasePipeline):

    def __init__(self, loris_getopt_obj, script_name):
        super().__init__(loris_getopt_obj, script_name)
        self.nifti_path = self.options_dict["nifti_path"]["value"]
        self.nifti_blake2 = blake2b(self.nifti_path.encode('utf-8')).hexdigest()
        self.nifti_md5 = hashlib.md5(self.nifti_path.encode()).hexdigest()
        self.json_path = self.options_dict["json_path"]["value"]
        self.json_blake2 = blake2b(self.json_path.encode('utf-8')).hexdigest()
        self.json_md5 = hashlib.md5(self.json_path.encode()).hexdigest()
        self.force = self.options_dict["force"]["value"]
        self.loris_scan_type = self.options_dict["loris_scan_type"]["value"]
        self.bypass_extra_checks = self.options_dict["bypass_extra_checks"]["value"]

        # ---------------------------------------------------------------------------------------------
        # Check the mri_upload table to see if the DICOM archive has been validated
        # ---------------------------------------------------------------------------------------------
        self.check_if_tarchive_validated_in_db()

        # ---------------------------------------------------------------------------------------------
        # Load the JSON file object with scan parameters if a JSON file was provided
        # ---------------------------------------------------------------------------------------------
        self.json_file_dict = self._load_json_sidecar_file()

        # ---------------------------------------------------------------------------------------------
        # Get the mapping dictionary between BIDS and MINC terms
        # ---------------------------------------------------------------------------------------------
        self.bids_mapping_dict = self.imaging_obj.param_type_db_obj.get_bids_to_minc_mapping_dict()

        # ---------------------------------------------------------------------------------------------
        # Check that the PatientName in NIfTI and DICOMs are the same and then validate the Subject IDs
        # ---------------------------------------------------------------------------------------------
        if self.tarchive_db_obj.tarchive_info_dict.keys():
            self._validate_nifti_patient_name_with_dicom_patient_name()
            self.subject_id_dict = self.imaging_obj.determine_subject_ids(
                self.tarchive_db_obj.tarchive_info_dict, self.scanner_dict['ScannerID']
            )
        else:
            self._determine_subject_ids_based_on_json_patient_name()
        self.validate_subject_ids()

        # ---------------------------------------------------------------------------------------------
        # Verify if the image/NIfTI file was not already registered into the database
        # ---------------------------------------------------------------------------------------------
        self._check_if_nifti_file_was_already_inserted()

        # ---------------------------------------------------------------------------------------------
        # Determine/create the session the file should be linked to
        # ---------------------------------------------------------------------------------------------
        self.get_session_info()
        if not self.session_db_obj.session_info_dict.keys():
            self.create_session()

        # ---------------------------------------------------------------------------------------------
        # Determine acquisition protocol (or register into mri_protocol_violated_scans and exits)
        # ---------------------------------------------------------------------------------------------
        if not self.loris_scan_type:
            self.scan_type_id = self._determine_acquisition_protocol()
            if not self.scan_type_id:
                self._move_to_trashbin()
                self._register_protocol_violated_scan()
                message = f"{self.nifti_path}'s acquisition protocol is 'unknown'."
                self.log_error_and_exit(message, lib.exitcode.UNKNOWN_PROTOCOL, is_error="Y", is_verbose="N")
            else:
                mri_scan_type_db_obj = MriScanType(self.db, self.verbose)
                self.scan_type_name = mri_scan_type_db_obj.get_scan_type_name_from_id(self.scan_type_id)

        # ---------------------------------------------------------------------------------------------
        # Run extra file checks to determine possible protocol violations
        # ---------------------------------------------------------------------------------------------
        self.warning_violations_list = []  # will store the list of warning violations found
        self.exclude_violations_list = []  # will store the list of exclude violations found
        if not self.bypass_extra_checks:
            self.violations_summary = self.imaging_obj.run_extra_file_checks(
                self.session_db_obj.session_info_dict['ProjectID'],
                self.session_db_obj.session_info_dict['SubprojectID'],
                self.session_db_obj.session_info_dict['Visit_label'],
                self.scan_type_id,
                self.json_file_dict
            )

        # ---------------------------------------------------------------------------------------------
        # Register files in the proper tables
        # ---------------------------------------------------------------------------------------------
        if self.violations_summary['exclude']:
            self._move_to_trashbin()
            self._register_violations_log(self.exclude_violations_list, self.trashbin_nifti_rel_path)
            self._register_violations_log(self.warning_violations_list, self.trashbin_nifti_rel_path)
            message = f"{self.nifti_path} violates exclusionary checks listed in mri_protocol_checks."
            self.log_error_and_exit(message, lib.exitcode.UNKNOWN_PROTOCOL, is_error="Y", is_verbose="N")
        else:
            self._move_to_assembly_and_insert_file_info()

        # ---------------------------------------------------------------------------------------------
        # Create the pic images
        # ---------------------------------------------------------------------------------------------
        # TODO: create the pic

    def _load_json_sidecar_file(self):
        """
        Loads the JSON file content into a dictionary.

        Note: if no JSON file was provided to the pipeline, the function will return an empty dictionary
        so that information to be stored in <parameter_file> later on can be added to the JSON dictionary.

        :return: dictionary with the information present in the JSON file
         :rtype: dict
        """
        json_path = self.options_dict["json_path"]["value"]

        if not json_path:
            return dict()

        with open(json_path) as json_file:
            json_data_dict = json.load(json_file)

        self._add_step_and_space_params_to_json_file_dict()

        return json_data_dict

    def _validate_nifti_patient_name_with_dicom_patient_name(self):
        """
        This function will validate that the PatientName present in the JSON side car file is the same as the
        one present in the <tarchive> table.

        Note: if no JSON file was provided to the script or if not "PatientName" was provided in the JSON file,
        the scripts will rely solely on the PatientName present in the <tarchive> table.
        """
        tarchive_pname = self.tarchive_db_obj.tarchive_info_dict["PatientName"]
        if "PatientName" not in self.json_file_dict:
            message = "PatientName not present in the JSON file or no JSON file provided along with" \
                      "the NIfTI file. Will rely on the PatientName stored in the DICOM files"
            self.log_info(message, is_error="N", is_verbose="Y")
            return

        nifti_pname = self.json_file_dict["PatientName"]
        if tarchive_pname != nifti_pname:
            err_msg = "PatientName in DICOM and NIfTI files differ."
            self.log_error_and_exit(err_msg, lib.exitcode.FILENAME_MISMATCH, is_error="Y", is_verbose="N")

    def _check_if_nifti_file_was_already_inserted(self):

        error_msg = None

        json_keys = self.json_file_dict.keys()
        if self.json_file_dict and "SeriesInstanceUID" in json_keys and "EchoTime" in json_keys:
            # verify that a file has not already be inserted with the same SeriesUID/EchoTime combination if
            # SeriesInstanceUID and EchoTime have been set in the JSON side car file
            echo_time = self.json_file_dict["EchoTime"]
            series_uid = self.json_file_dict["SeriesInstanceUID"]
            match = self.imaging_obj.grep_file_info_from_series_uid_and_echo_time(series_uid, echo_time)
            if match:
                error_msg = f"There is already a file registered in the files table with SeriesUID {series_uid} and" \
                            f" EchoTime {echo_time}. The already registered file is {match['File']}"

            # If force option has been used, check that there is no matching SeriesUID/EchoTime entry in tarchive_series
            if self.force:
                tar_echo_time = echo_time * 1000
                match_tar = self.tarchive_db_obj.create_tarchive_dict_from_series_uid_and_echo_time(
                    series_uid, tar_echo_time
                )
                if match_tar:
                    error_msg = f"Found a DICOM archive containing DICOM files with the same SeriesUID ({series_uid})" \
                                f" and EchoTime ({tar_echo_time}) as the one present in the JSON side car file. " \
                                f" The DICOM archive location containing those DICOM files is " \
                                f" {self.tarchive_db_obj.tarchive_info_dict['ArchiveLocation']}. Please, rerun " \
                                f" <run_nifti_insertion.py> with either --upload_id or --tarchive_path option."

        # verify that a file with the same MD5 or blake2b hash has not already been inserted
        md5_match = self.imaging_obj.grep_file_info_from_hash(self.nifti_md5)
        blake2b_match = self.imaging_obj.grep_file_info_from_hash(self.nifti_blake2)
        if md5_match:
            error_msg = f"There is already a file registered in the files table with MD5 hash {self.nifti_md5}." \
                        f" The already registered file is {md5_match['File']}"
        elif blake2b_match:
            error_msg = f"There is already a file registered in the files table with Blake2b hash {self.nifti_blake2}." \
                        f" The already registered file is {blake2b_match['File']}"

        if error_msg:
            self.log_error_and_exit(error_msg, lib.exitcode.FILE_NOT_UNIQUE, is_error="Y", is_verbose="N")

    def _determine_subject_ids_based_on_json_patient_name(self):
        dicom_header = self.config_db_obj.get_config('lookupCenterNameUsing')
        dicom_value = self.json_file_dict[dicom_header]

        try:
            self.subject_id_dict = self.config_file.get_subject_ids(self.db, dicom_value, None)
            self.subject_id_dict["PatientName"] = dicom_value
        except AttributeError:
            message = "Config file does not contain a get_subject_ids routine. Upload will exit now."
            self.log_error_and_exit(message, lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE, is_error="Y", is_verbose="N")

        self.log_info("Determined subject IDs based on PatientName stored in JSON file", is_error="N", is_verbose="Y")

    def _determine_acquisition_protocol(self):

        nifti_name = os.path.basename(self.nifti_path)
        scan_param = self.json_file_dict

        # get scanner ID if not already figured out
        if "ScannerID" not in self.scanner_dict.keys():
            self.scanner_dict['ScannerID'] = self.imaging_obj.get_scanner_id_from_json_data(
                self.json_file_dict, self.site_dict['CenterID']
            )

        # get the list of lines in the mri_protocol table that apply to the given scan based on the protocol group
        protocols_list = self.imaging_obj.mri_prot_db_obj.get_list_of_possible_protocols_based_on_session_info(
            self.session_db_obj.session_info_dict['ProjectID'],
            self.session_db_obj.session_info_dict['SubprojectID'],
            self.session_db_obj.session_info_dict['CenterID'],
            self.session_db_obj.session_info_dict['Visit_label'],
            self.scanner_dict['ScannerID']
        )

        if not len(protocols_list):
            message = f"Warning! No protocol group can be used to determine the scan type of {nifti_name}." \
                      f" Incorrect/incomplete setup of table mri_protocol_group_target."
            self.log_info(message, is_error="N", is_verbose="Y")
            return False

        mri_protocol_group_ids = set(map(lambda x: x['MriProtocolGroupID'], protocols_list))
        if len(mri_protocol_group_ids) > 1:
            message = f"Warning! More than one protocol group can be used to identify the scan type of {nifti_name}." \
                      f" Ambiguous setup of table mri_protocol_group_target."
            self.log_info(message, is_error="N", is_verbose="Y")
            return False

        # look for matching protocols
        matching_protocols_list = []
        for protocol in protocols_list:
            if protocol['series_description_regex']:
                if re.search(rf"{protocol['series_description_regex']}", scan_param['SeriesDescription']):
                    matching_protocols_list.append(protocol['Scan_type'])
            elif self.imaging_obj.is_scan_protocol_matching_db_protocol(protocol, scan_param):
                matching_protocols_list.append(protocol['Scan_type'])

        # if more than one protocol matching, return False, otherwise, return the scan type ID
        if not matching_protocols_list:
            message = f'Warning! Could not identify protocol of {nifti_name}.'
            self.log_info(message, is_error='N', is_verbose='Y')
            return False
        elif len(matching_protocols_list) > 1:
            message = f'Warning! More than one protocol matched the image acquisition parameters of {nifti_name}.'
            self.log_info(message, is_error='N', is_verbose='Y')
            return False
        else:
            scan_type_id = matching_protocols_list[0]
            message = f'Acquisition protocol ID for the file to insert is {scan_type_id}'
            self.log_info(message, is_error='N', is_verbose='Y')
            return scan_type_id

    def _add_step_and_space_params_to_json_file_dict(self):
        step_params = self.imaging_obj.get_nifti_image_step_parameters(self.nifti_path)
        length_params = self.imaging_obj.get_nifti_image_length_parameters(self.nifti_path)
        self.json_file_dict['xstep'] = step_params[0]
        self.json_file_dict['ystep'] = step_params[1]
        self.json_file_dict['zstep'] = step_params[2]
        self.json_file_dict['xspace'] = length_params[0]
        self.json_file_dict['yspace'] = length_params[1]
        self.json_file_dict['zspace'] = length_params[2]
        if len(length_params) == 4:
            self.json_file_dict['time'] = length_params[3]

    def _move_to_assembly_and_insert_file_info(self):

        self.assembly_nifti_rel_path = self._determine_new_nifti_assembly_rel_path()
        self._create_destination_dir_and_move_image_files('assembly')

        self.file_id = self._register_into_files_and_parameter_file(self.assembly_nifti_rel_path)

        if self.violations_summary['warning']:
            self._register_violations_log(self.warning_violations_list, self.assembly_nifti_rel_path)

    def _determine_new_nifti_assembly_rel_path(self):

        study_prefix = self.config_db_obj.get_config('prefix')
        cand_id = self.subject_id_dict['CandID']
        visit = self.subject_id_dict['visitLabel']

        curr_nifti_path = self.nifti_path
        nifti_ext = re.search(r"\.nii(\.gz)?$", curr_nifti_path).group()

        file_nb = 1
        new_nifti_name = '_'.join([study_prefix, cand_id, visit, self.scan_type_name, format(file_nb, '03d')]) \
                         + nifti_ext
        new_nifti_rel_dir = os.path.join('assembly', cand_id, visit, 'mri', 'native')
        while os.path.exists(os.path.join(self.data_dir, new_nifti_rel_dir, new_nifti_name)):
            file_nb += 1
            new_nifti_name = '_'.join([study_prefix, cand_id, visit, self.scan_type_name, format(file_nb, '03d')]) \
                             + nifti_ext

        return os.path.join('assembly', cand_id, visit, 'mri', 'native', new_nifti_name)

    def _move_to_trashbin(self):
        self.trashbin_nifti_rel_path = os.path.join(
            'trashbin',
            re.sub(r'\.log', '', os.path.basename(self.log_obj.log_file)),
            os.path.basename(self.nifti_path)
        )
        self._create_destination_dir_and_move_image_files('trashbin')

    def _create_destination_dir_and_move_image_files(self, destination):

        nifti_rel_path = self.assembly_nifti_rel_path if destination == 'assembly' else self.trashbin_nifti_rel_path
        json_rel_path = re.sub(r"\.nii(\.gz)?$", '.json', nifti_rel_path) if self.json_path else None

        absolute_dir_path = os.path.join(self.data_dir, os.path.dirname(nifti_rel_path))
        absolute_nifti_path = os.path.join(self.data_dir, nifti_rel_path)
        absolute_json_path = os.path.join(self.data_dir, json_rel_path) if self.json_path else None

        self.create_dir(absolute_dir_path)

        file_type_to_move_list = ['nifti', 'json'] if self.json_path else ['nifti']
        for file_type in file_type_to_move_list:
            original_file_path = self.nifti_path if file_type == 'nifti' else self.json_path
            new_file_path = absolute_nifti_path if file_type == 'nifti' else absolute_json_path
            self.move_file(original_file_path, new_file_path)

        if destination == 'assembly':
            # TODO bval and bval handling...
            self.json_file_dict['file_blake2b_hash'] = self.nifti_blake2
            if self.json_path:
                self.json_file_dict['bids_json_file'] = json_rel_path
                self.json_file_dict['bids_json_file_blake2b_hash'] = self.json_blake2

    def _register_protocol_violated_scan(self):

        scan_param = self.json_file_dict
        tarchive_param = self.tarchive_db_obj.tarchive_info_dict
        patient_name = None
        if "PatientName" in scan_param.keys():
            patient_name = scan_param["PatientName"]
        elif "PatientName" in tarchive_param.keys():
            patient_name = tarchive_param["PatientName"]
        info_to_insert_dict = {
            "CandID": self.subject_id_dict["CandID"],
            "PSCID": self.subject_id_dict["PSCID"],
            "TarchiveID": tarchive_param["TarchiveID"],
            "time_run": datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            "series_description": scan_param["SeriesDescription"],
            "minc_location": self.trashbin_nifti_rel_path,
            "PatientName": patient_name,
            "TR_range": scan_param["RepetitionTime"] if "RepetitionTime" in scan_param.keys() else None,
            "TE_range": scan_param["EchoTime"] if "EchoTime" in scan_param.keys() else None,
            "TI_range": scan_param["InversionTime"] if "InversionTime" in scan_param.keys() else None,
            "slice_thickness_range": scan_param["SliceThickness"] if "SliceThickness" in scan_param.keys() else None,
            "xspace_range": scan_param["xspace"] if "xspace" in scan_param.keys() else None,
            "yspace_range": scan_param["yspace"] if "yspace" in scan_param.keys() else None,
            "zspace_range": scan_param["zspace"] if "zspace" in scan_param.keys() else None,
            "xstep_range": scan_param["xstep"] if "xstep" in scan_param.keys() else None,
            "ystep_range": scan_param["ystep"] if "ystep" in scan_param.keys() else None,
            "zstep_range": scan_param["zstep"] if "zstep" in scan_param.keys() else None,
            "time_range": scan_param["time"] if "time" in scan_param.keys() else None,
            "SeriesUID": scan_param["SeriesUID"] if "SeriesUID" in scan_param.keys() else None,
            "image_type": scan_param["ImageType"] if "ImageType" in scan_param.keys() else None,
            "MriProtocolGroupID": scan_param["MriProtocolGroupID"]
        }
        prot_viol_db_obj = MriProtocolViolatedScans(self.db, self.verbose)
        prot_viol_db_obj.insert_protocol_violated_scans(info_to_insert_dict)

    def _register_violations_log(self, violations_list, file_path):
        scan_param = self.json_file_dict
        base_info_dict = {
            'TimeRun': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'SeriesUID': scan_param['SeriesInstanceUID'] if 'SeriesInstanceUID' in scan_param.keys() else None,
            'TarchiveID': self.tarchive_db_obj.tarchive_info_dict['TarchiveID'],
            'MincFile': file_path,
            'PatientName': self.subject_id_dict['PatientName'],
            'CandID': self.subject_id_dict['CandID'],
            'Visit_label': self.subject_id_dict['visitLabel'],
            'Scan_type': self.scan_type_id
        }
        for violation_dict in violations_list:
            info_to_insert_dict = base_info_dict | violation_dict
            self.imaging_obj.mri_viol_log_db_obj.insert_violations_log(info_to_insert_dict)

    def _register_into_files_and_parameter_file(self, nifti_rel_path):
        """
        Registers the image into files and file_parameter via the lib.imaging library.

        :param nifti_rel_path: relative path to the imaging file to use for the File column of the files table
         :type nifti_rel_path: str

        :return: file ID of the inserted image
         :rtype: int
        """

        scan_param = self.json_file_dict
        acquisition_date = datetime.datetime.fromisoformat(scan_param['AcquisitionDateTime']).strftime("%Y-%m-%d")
        file_type = self.imaging_obj.determine_file_type(nifti_rel_path)
        if not file_type:
            message = f'Could not determine file type for {nifti_rel_path}. No entry found in ImagingFileTypes table'
            self.log_error_and_exit(message, lib.exitcode.SELECT_FAILURE, is_error='Y', is_verbose='N')

        files_insert_info_dict = {
            'SessionID': self.session_db_obj.session_info_dict['ID'],
            'File': nifti_rel_path,
            'SeriesUID': scan_param['SeriesInstanceUID'] if 'SeriesInstanceUID' in scan_param.keys() else None,
            'EchoTime': scan_param['EchoTime'],
            'CoordinateSpace': 'native',
            'OutputType': 'native',
            'AcquisitionProtocolID': self.scan_type_id,
            'FileType': file_type,
            'InsertedByUserID': getpass.getuser(),
            'InsertTime': datetime.datetime.now().timestamp(),
            'Caveat': 1 if self.warning_violations_list else 0,
            'TarchiveSource': self.tarchive_db_obj.tarchive_info_dict['TarchiveID'],
            'ScannerID': self.scanner_dict['ScannerID'],
            'AcquisitionDate': acquisition_date,
            'SourceFileID': None
        }
        file_id = self.imaging_obj.insert_imaging_file(files_insert_info_dict, self.json_file_dict)

        return file_id

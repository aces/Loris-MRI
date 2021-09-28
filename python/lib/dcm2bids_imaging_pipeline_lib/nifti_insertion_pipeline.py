import datetime
import getpass
import hashlib
import json
import lib.exitcode
import os
import re
from lib.database_lib.files import Files
from lib.database_lib.mri_protocol import MriProtocol
from lib.database_lib.mri_protocol_checks import MriProtocolChecks
from lib.database_lib.mri_protocol_violated_scans import MriProtocolViolatedScans
from lib.database_lib.mri_violations_log import MriViolationsLog
from lib.database_lib.parameter_file import ParameterFile
from lib.database_lib.parameter_type import ParameterType
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline
from lib.imaging import Imaging
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
        # Load imaging class
        # ---------------------------------------------------------------------------------------------
        self.imaging_obj = Imaging(self.db, self.verbose, self.config_file)

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
        self.param_type_obj = ParameterType(self.db, self.verbose)
        self.bids_mapping_dict = self.param_type_obj.get_bids_to_minc_mapping_dict()

        # ---------------------------------------------------------------------------------------------
        # Check that the PatientName in NIfTI and DICOMs are the same and then validate the Subject IDs
        # ---------------------------------------------------------------------------------------------
        if self.tarchive_db_obj.tarchive_info_dict.keys():
            self._validate_nifti_patient_name_with_dicom_patient_name()
            self.subject_id_dict = self.determine_subject_ids(self.scanner_dict['ScannerID'])
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
                # TODO move file to trashbin
                self._register_protocol_violated_scan()
                message = f"{self.nifti_path}'s acquisition protocol is 'unknown'."
                self.log_error_and_exit(message, lib.exitcode.UNKNOWN_PROTOCOL, is_error="Y", is_verbose="N")

        # ---------------------------------------------------------------------------------------------
        # Run extra file checks to determine possible protocol violations
        # ---------------------------------------------------------------------------------------------
        self.warning_violations_list = []  # will store the list of warning violations found
        self.exclude_violations_list = []  # will store the list of exclude violations found
        if not self.bypass_extra_checks:
            self._run_extra_file_checks()

        # ---------------------------------------------------------------------------------------------
        # Register files in the proper tables
        # ---------------------------------------------------------------------------------------------
        if self.exclude_violations_list:
            # TODO move file to trashbin
            self._register_violations_log(self.exclude_violations_list)
            self._register_violations_log(self.warning_violations_list)
            message = f"{self.nifti_path} violates 'exclude' checks listed in mri_protocol_checks."
            self.log_error_and_exit(message, lib.exitcode.UNKNOWN_PROTOCOL, is_error="Y", is_verbose="N")
        elif self.warning_violations_list:
            # TODO move file to assembly
            self.file_id = self._register_files()
            self._register_parameter_file()
            self._register_violations_log(self.warning_violations_list)
        else:
            # TODO move file to assembly
            self.file_id = self._register_files()
            self._register_parameter_file()

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
        # self.imaging_obj.map_bids_param_to_loris_param(json_data_dict)
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

        files_obj = Files(self.db, self.verbose)
        error_msg = None

        json_keys = self.json_file_dict.keys()
        if self.json_file_dict and "SeriesInstanceUID" in json_keys and "EchoTime" in json_keys:
            # verify that a file has not already be inserted with the same SeriesUID/EchoTime combination if
            # SeriesInstanceUID and EchoTime have been set in the JSON side car file
            echo_time = self.json_file_dict["EchoTime"]
            series_uid = self.json_file_dict["SeriesInstanceUID"]
            match = files_obj.find_file_with_series_uid_and_echo_time(series_uid, echo_time)
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
        md5_match = files_obj.find_file_with_hash(self.nifti_md5)
        blake2b_match = files_obj.find_file_with_hash(self.nifti_blake2)
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
            self.mri_scanner_db_obj.determine_scanner_information(
                {
                    "ScannerManufacturer": self.json_file_dict["Manufacturer"],
                    "ScannerSoftwareVersion": self.json_file_dict["SoftwareVersions"],
                    "ScannerSerialNumber": self.json_file_dict["DeviceSerialNumber"],
                    "ScannerModel": self.json_file_dict["ManufacturersModelName"],
                },
                self.site_dict
            )

        # get the list of lines in the mri_protocol table that apply to the given scan based on the protocol group
        mri_protocol_db_obj = MriProtocol(self.db, self.verbose)
        protocols_list = mri_protocol_db_obj.get_list_of_possible_protocols_based_on_session_info(
            self.session_db_obj.session_info_dict, self.scanner_dict['ScannerID']
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
            elif self._is_scan_protocol_matching_db_protocol(protocol):
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
            return matching_protocols_list[0]

    def _run_extra_file_checks(self):

        # get list of lines in mri_protocol_checks that apply to the given scan based on the protocol group
        mri_prot_check_db_obj = MriProtocolChecks(self.db, self.verbose)
        checks_list = mri_prot_check_db_obj.get_list_of_possible_protocols_based_on_session_info(
            self.session_db_obj.session_info_dict, self.scan_type_id
        )

        distinct_headers = set(map(lambda x: x['Header'], checks_list))
        for header in distinct_headers:
            if header not in self.json_file_dict.keys():
                header = self.bids_mapping_dict[header] if header in self.bids_mapping_dict.keys() else None
                if not header:
                    continue

            warning_violations = self._check_violations_per_severity(checks_list, header, 'warning')
            exclude_violations = self._check_violations_per_severity(checks_list, header, 'exclude')
            if warning_violations:
                self.warning_violations_list.append(warning_violations)
            if exclude_violations:
                self.exclude_violations_list.append(exclude_violations)

    def _check_violations_per_severity(self, checks_list, header, severity):

        hdr_checks_list = [c for c in checks_list if c['Header'] == header and c['Severity'] == severity]

        valid_ranges = []
        valid_regexs = []
        for check in hdr_checks_list:
            if check['ValidMin'] or check['ValidMax']:
                valid_min = float(check['ValidMin']) if check['ValidMin'] else None
                valid_max = float(check['ValidMax']) if check['ValidMax'] else None
                valid_ranges.append([valid_min, valid_max])
            if check['ValidRegex']:
                valid_regexs.append(check['ValidRegex'])

        scan_param = self.json_file_dict[header]
        passes_range_check = bool(len([
            True for v in valid_ranges if self.in_range(scan_param, v[0], v[1])]
        )) if valid_ranges else True
        passes_regex_check = bool(len([
            True for r in valid_regexs if re.match(r, scan_param)
        ])) if valid_regexs else True

        if passes_regex_check and passes_range_check:
            return None
        else:
            return {
                'Severity': severity,
                'Header': header,
                'Value': scan_param,
                'ValidRange': ','.join([f"{v[0]}-{v[1]}" for v in valid_ranges]) if valid_ranges else None,
                'ValidRegex': ','.join(valid_regexs) if valid_regexs else None,
                'MriProtocolChecksGroupID': hdr_checks_list[0]['MriProtocolChecksGroupID']
            }

    def _is_scan_protocol_matching_db_protocol(self, db_prot):

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

        scan_param = self.json_file_dict
        scan_tr = self.json_file_dict['RepetitionTime'] * 1000
        scan_te = self.json_file_dict['EchoTime'] * 1000
        scan_ti = self.json_file_dict['InversionTime'] * 1000

        scan_slice_thick = self.json_file_dict['SliceThickness']
        scan_img_type = self.json_file_dict['ImageType']

        # TODO handle image type: note: img_type = ["ORIGINAL", "PRIMARY", "M", "ND", "NORM"] in JSON
        if ("time" not in scan_param or self.in_range(scan_param['time'], db_prot['time_min'], db_prot['time_max'])) \
                and self.in_range(scan_tr, db_prot['TR_min'], db_prot['TR_max']) \
                and self.in_range(scan_te, db_prot['TE_min'], db_prot['TE_max']) \
                and self.in_range(scan_ti, db_prot['TI_min'], db_prot['TI_max']) \
                and self.in_range(scan_param['xstep'], db_prot['xstep_min'], db_prot['xstep_max']) \
                and self.in_range(scan_param['ystep'], db_prot['ystep_min'], db_prot['ystep_max']) \
                and self.in_range(scan_param['zstep'], db_prot['zstep_min'], db_prot['zstep_max']) \
                and self.in_range(scan_param['xspace'], db_prot['xspace_min'], db_prot['xspace_max']) \
                and self.in_range(scan_param['yspace'], db_prot['yspace_min'], db_prot['yspace_max']) \
                and self.in_range(scan_param['zspace'], db_prot['zspace_min'], db_prot['zspace_max']) \
                and self.in_range(scan_slice_thick, db_prot['slice_thickness_min'], db_prot['slice_thickness_max']) \
                and (not db_prot['image_type'] or scan_img_type == db_prot['image_type']):
            return True

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
            "minc_location": "",  # TODO determine new location
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

    def _register_violations_log(self, violations_list):

        scan_param = self.json_file_dict
        base_info_dict = {
            'TimeRun': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'SeriesUID': scan_param['SeriesInstanceUID'] if 'SeriesInstanceUID' in scan_param.keys() else None,
            'TarchiveID': self.tarchive_db_obj.tarchive_info_dict['TarchiveID'],
            'MincFile': '',  # TODO determine new location
            'PatientName': self.subject_id_dict['PatientName'],
            'CandID': self.subject_id_dict['CandID'],
            'Visit_label': self.subject_id_dict['visitLabel'],
            'Scan_type': self.scan_type_id
        }
        for violation_dict in violations_list:
            info_to_insert_dict = base_info_dict | violation_dict
            prot_viol_log_db_obj = MriViolationsLog(self.db, self.verbose)
            prot_viol_log_db_obj.insert_violations_log(info_to_insert_dict)

    def _register_files(self):

        scan_param = self.json_file_dict
        acquisition_date = datetime.datetime.fromisoformat(scan_param['AcquisitionDateTime']).strftime("%Y-%m-%d")
        files_insert_info_dict = {
            'SessionID': self.session_db_obj.session_info_dict['ID'],
            'File': '', # TODO determine file path
            'SeriesUID': scan_param['SeriesInstanceUID'] if 'SeriesInstanceUID' in scan_param.keys() else None,
            'EchoTime': scan_param['EchoTime'],
            'CoordinateSpace': 'native',
            'OutputType': 'native',
            'AcquisitionProtocolID': self.scan_type_id,
            'FileType': 'nii',
            'InsertedByUserID': getpass.getuser(),
            'InsertTime': datetime.datetime.now().timestamp(),
            'Caveat': 1 if self.warning_violations_list else 0,
            'TarchiveSource': self.tarchive_db_obj.tarchive_info_dict['TarchiveID'],
            'ScannerID': self.scanner_dict['ScannerID'],
            'AcquisitionDate': acquisition_date,
            'SourceFileID': None
        }

        files_db_obj = Files(self.db, self.verbose)
        file_id = files_db_obj.insert_files(files_insert_info_dict)

        return file_id

    def _register_parameter_file(self):

        scan_param = self.json_file_dict

        for param in scan_param:
            param_type_id = None
            if param in self.bids_mapping_dict.values():
                param_type_id = self.param_type_obj.get_parameter_type_id(param_alias=param)
            else:
                param_type_id = self.param_type_obj.get_parameter_type_id(param_name=param)

            if not param_type_id:
                # create a new entry for the parameter in parameter_type
                param_type_id = self.param_type_obj.insert_parameter_type(
                    {
                        'Name': param,
                        'Alias': None,
                        'Type': 'text',
                        'Description': f'{param} magically created by dcm2bids nifti_insertion_pipeline.py',
                        'SourceFrom': 'parameter_file',
                        'Queryable': 0
                    }
                )

            if type(scan_param[param]) == list:
                if type(scan_param[param][0]) in [float, int]:
                    scan_param[param] = [str(f) for f in scan_param[param]]
                scan_param[param] = f"[{', '.join(scan_param[param])}]"

            param_file_insert_info_dict = {
                'ParameterTypeID': param_type_id,
                'FileID': self.file_id,
                'Value': scan_param[param],
                'InsertTime': datetime.datetime.now().timestamp()
            }

            param_file_db_obj = ParameterFile(self.db, self.verbose)
            param_file_db_obj.insert_parameter_file(param_file_insert_info_dict)

    @staticmethod
    def in_range(value, field_min, field_max):

        # return True when parameter min and max values are not defined (a.k.a. no restrictions in mri_protocol)
        if not field_min and not field_max:
            return True

        # return True if min & max are defined and value is within the range
        if field_min and field_max and field_min <= value <= field_max:
            return True

        # return True if only min is defined and value is <= min
        if field_min and not field_max and field_min <= value:
            return True

        # return True if only max is defined and value is >= max
        if field_max and not field_min and value <= field_max:
            return True

        # if we got this far, then value is out of range
        return False

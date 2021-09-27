import datetime
import hashlib
import json
import lib.exitcode
import os
import re
from functools import reduce
from lib.database_lib.files import Files
from lib.database_lib.mri_protocol import MriProtocol
from lib.database_lib.mri_protocol_violated_scans import MriProtocolViolatedScans
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
        # Determine acquisition protocol
        # ---------------------------------------------------------------------------------------------
        if not self.loris_scan_type:
            scan_type_id = self._determine_acquisition_protocol()
            if not scan_type_id:
                self._register_protocol_violated_scan()
                message = f"{self.nifti_path}'s acquisition protocol is 'unknown'."
                self.log_error_and_exit(message, lib.exitcode.UNKNOWN_PROTOCOL, is_error="Y", is_verbose="N")

            if not self.bypass_extra_checks:
                self._run_extra_file_checks()

        # TODO: plan
        # 17. insert into Db (files + parameter_file)
        # 18. update mri violations log
        # 19. create pics

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
        # TODO might be best to move the mapping in SQL and instead insert in parameter file only the BIDS terms
        self.imaging_obj.map_bids_param_to_loris_param(json_data_dict)
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
            error_msg = f"There is already a file registered in the files table with Blake2b hash {self.nifti_blake2}."\
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
            self.session_db_obj.session_info_dict, self.scanner_dict["ScannerID"]
        )

        if not len(protocols_list):
            message = f"Warning! No protocol group can be used to determine the scan type of {nifti_name}." \
                      f" Incorrect/incomplete setup of table mri_protocol_group_target."
            self.log_info(message, is_error="N", is_verbose="Y")
            return False

        mri_protocol_group_ids = reduce(lambda x: x["MriProtocolGroupID"], protocols_list)
        if len(mri_protocol_group_ids) > 1:
            message = f"Warning! More than one protocol group can be used to identify the scan type of {nifti_name}." \
                      f" Ambiguous setup of table mri_protocol_group_target."
            self.log_info(message, is_error="N", is_verbose="Y")
            return False

        self.json_file_dict['MriProtocolGroupID'] = mri_protocol_group_ids[0]

        # look for matching protocols
        matching_protocols_list = []
        for protocol in protocols_list:
            if protocol["series_description_regex"]:
                if re.search(rf"{protocol['series_description_regex']}", scan_param['SeriesDescription']):
                    matching_protocols_list.append(protocol["Scan_type"])
            elif self.is_scan_protocol_matching_db_protocol(protocol):
                matching_protocols_list.append(protocol["Scan_type"])

        # if more than one protocol matching, return False, otherwise, return the scan type ID
        if len(matching_protocols_list) > 1:
            message = f"Warning! More than one protocol matched the image acquisition parameters of {nifti_name}."
            self.log_info(message, is_error="N", is_verbose="Y")
            return False
        else:
            return matching_protocols_list[0]

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
            "time_run": datetime.datetime.now(),
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

    def _run_extra_file_checks(self):
        # do extra file checks
        print("hello")

    def is_scan_protocol_matching_db_protocol(self, db_prot):

        step_params = self.imaging_obj.get_nifti_image_step_parameters(self.nifti_path)
        length_params = self.imaging_obj.get_nifti_image_length_parameters(self.nifti_path)
        self.json_file_dict["xstep"] = step_params[0]
        self.json_file_dict["ystep"] = step_params[1]
        self.json_file_dict["zstep"] = step_params[2]
        self.json_file_dict["xspace"] = length_params[0]
        self.json_file_dict["yspace"] = length_params[1]
        self.json_file_dict["zspace"] = length_params[2]
        self.json_file_dict["time"] = length_params[3] if len(length_params) == 4 else None
        scan_param = self.json_file_dict
        scan_slice_thick = self.json_file_dict["SliceThickness"]
        img_type = self.json_file_dict["ImageType"]
        # TODO handle image type: note: img_type = ["ORIGINAL", "PRIMARY", "M", "ND", "NORM"] in JSON

        if self.in_range(scan_param["RepetitionTime"], db_prot["TR_min"], db_prot["TR_max"]) \
                and self.in_range(scan_param["EchoTime"], db_prot["TE_min"], db_prot["TE_max"]) \
                and self.in_range(scan_param["InversionTime"], db_prot["TI_min"], db_prot["TI_max"]) \
                and self.in_range(scan_param["xstep"], db_prot["xstep_min"], db_prot["xstep_max"]) \
                and self.in_range(scan_param["ystep"], db_prot["ystep_min"], db_prot["ystep_max"]) \
                and self.in_range(scan_param["zstep"], db_prot["zstep_min"], db_prot["zstep_max"]) \
                and self.in_range(scan_param["xspace"], db_prot["xspace_min"], db_prot["xspace_max"]) \
                and self.in_range(scan_param["yspace"], db_prot["yspace_min"], db_prot["yspace_max"]) \
                and self.in_range(scan_param["zspace"], db_prot["zspace_min"], db_prot["zspace_max"]) \
                and self.in_range(scan_param["time"], db_prot["time_min"], db_prot["time_max"]) \
                and self.in_range(scan_slice_thick, db_prot["slice_thickness_min"], db_prot["slice_thickness_max"]) \
                and (not db_prot['image_type'] or img_type == db_prot['image_type']):
            return True

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

"""This class performs database queries and common imaging checks (MRI...)"""

import os
import datetime
import json
import nibabel as nib
import re
import tarfile

from nilearn import image, plotting
from pyblake2 import blake2b

from lib.database_lib.config import Config
from lib.database_lib.files import Files
from lib.database_lib.mri_candidate_errors import MriCandidateErrors
from lib.database_lib.mri_protocol import MriProtocol
from lib.database_lib.mri_protocol_checks import MriProtocolChecks
from lib.database_lib.mri_protocol_violated_scans import MriProtocolViolatedScans
from lib.database_lib.mri_scan_type import MriScanType
from lib.database_lib.mri_scanner import MriScanner
from lib.database_lib.mri_violations_log import MriViolationsLog
from lib.database_lib.parameter_file import ParameterFile
from lib.database_lib.parameter_type import ParameterType

__license__ = "GPLv3"


class Imaging:
    """
    This class performs database queries for imaging dataset (MRI, PET...).

    :Example:

        from lib.imaging  import Imaging
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        imaging = Imaging(db, verbose)

        # Get file type for the imaging file
        file_type = imaging.get_file_type(img_file)

        # Grep a FileID based on a blake2b hash
        file_id = imaging.grep_file_id_from_hash(blake2)

        ...
    """

    def __init__(self, db, verbose, config_file=None):
        """
        Constructor method for the Imaging class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        :param config_file: config file with custom functions
         :type config_file: str
        """

        self.db = db
        self.verbose = verbose
        self.config_file = config_file
        self.config_db_obj = Config(self.db, self.verbose)
        self.files_db_obj = Files(db, verbose)
        self.mri_cand_errors_db_obj = MriCandidateErrors(db, verbose)
        self.mri_prot_db_obj = MriProtocol(db, verbose)
        self.mri_prot_check_db_obj = MriProtocolChecks(db, verbose)
        self.mri_prot_viol_scan_db_obj = MriProtocolViolatedScans(db, verbose)
        self.mri_scan_type_db_obj = MriScanType(db, verbose)
        self.mri_scanner_db_obj = MriScanner(db, verbose)
        self.mri_viol_log_db_obj = MriViolationsLog(db, verbose)
        self.param_type_db_obj = ParameterType(db, verbose)
        self.param_file_db_obj = ParameterFile(db, verbose)

    def determine_file_type(self, file):
        """
        Greps all file types defined in the ImagingFileTypes table and checks
        if the file matches one of the file type. If no match is found, the
        script will exit with error message and error code.

        :param file: file's name
         "type file: str

        :return: file's type
         :rtype: str
        """

        imaging_file_types = self.db.pselect(query="SELECT type FROM ImagingFileTypes")

        # if the file type cannot be found in the database, exit now
        file_type = None
        for type in imaging_file_types:
            regex_match = r'' + type['type'] + r'(\.gz)?$'
            if re.search(regex_match, file):
                file_type = type['type']

        return file_type

    def grep_file_info_from_hash(self, hash_string):
        """
        Greps the file ID from the files table. If it cannot be found, the method will return None.

        :param hash_string: blake2b or md5 hash
         :type hash_string: str

        :return: dictionary with files table content of the found file
         :rtype: dict
        """
        return self.files_db_obj.find_file_with_hash(hash_string)

    def grep_file_info_from_series_uid_and_echo_time(self, series_uid, echo_time, phase_enc_dir, echo_number):
        """
        Greps the file ID from the files table. If it cannot be found, the method will return None.

        :param series_uid: Series Instance UID of the file to look for
         :type series_uid: str
        :param echo_time: Echo Time of the file to look for
         :type echo_time: float
        :param phase_enc_dir: Phase Encoding Direction of the file to look for
         :type phase_enc_dir: str
        :param echo_number: Echo Number of the file to look for
         :type echo_number: int

        :return: dictionary with files table content of the found file
        :rtype: dict
        """
        return self.files_db_obj.find_file_with_series_uid_and_echo_time(
            series_uid, echo_time, phase_enc_dir, echo_number
        )

    def insert_imaging_file(self, file_info_dict, parameter_file_data_dict):
        """
        Inserts the imaging file and its information into the files and parameter_file tables.

        :param file_info_dict: dictionary with values to insert into files' table
         :type file_info_dict: dict
        :param parameter_file_data_dict: dictionary with values to insert into parameter_file's table
         :type parameter_file_data_dict: dict

        :return: file ID
         :rtype: int
        """

        # insert info from file_info into files
        file_id = self.files_db_obj.insert_files(file_info_dict)

        # insert info from file_data into parameter_file
        for key, value in parameter_file_data_dict.items():
            self.insert_parameter_file(file_id, key, value)

        return file_id

    def insert_parameter_file(self, file_id, parameter_name, value):
        """
        Insert a row into the parameter_file table for the provided FileID,
        parameter Name and Value

        :param file_id       : FileID
         :type file_id       : int
        :param parameter_name: Name of the parameter from parameter_type
         :type parameter_name: str
        :param value         : Value to insert into parameter_file
         :type value         : str
        """

        # convert list values into strings that could be inserted into parameter_file
        if type(value) == list:
            if type(value[0]) in [float, int]:
                value = [str(f) for f in value]
            value = f"[{', '.join(value)}]"

        # Gather column name & values to insert into parameter_file
        param_type_id = self.get_parameter_type_id(parameter_name)
        param_file_insert_info_dict = {
            'ParameterTypeID': param_type_id,
            'FileID': file_id,
            'Value': value,
            'InsertTime': datetime.datetime.now().timestamp()
        }

        pf_entry = self.param_file_db_obj.get_parameter_file_for_file_id_param_type_id(file_id, param_type_id)
        if pf_entry:
            self.param_file_db_obj.update_parameter_file(value, pf_entry['ParameterFileID'])
        else:
            self.param_file_db_obj.insert_parameter_file(param_file_insert_info_dict)

    def insert_mri_candidate_errors(self, patient_name, tarchive_id, scan_param, file_rel_path, reason):
        """
        Insert a row into MriCandidateErrors table.

        :param patient_name: PatientName associated to the file to insert
         :type patient_name: str
        :param tarchive_id: TarchiveID of the archive the file has been derived from
         :type tarchive_id: int
        :param scan_param: parameters of the image to insert
         :type scan_param: dict
        :param file_rel_path: relative path to the file in trashbin
         :type file_rel_path: str
        :param reason: reason for the candidate mismatch error
         :type reason: str
        """

        info_to_insert_dict = {
            "TimeRun": datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            "SeriesUID": scan_param["SeriesUID"] if "SeriesUID" in scan_param.keys() else None,
            "TarchiveID": tarchive_id,
            "MincFile": file_rel_path,
            "PatientName": patient_name,
            "Reason": reason,
            "EchoTime": scan_param["EchoTime"] if "EchoTime" in scan_param.keys() else None
        }
        self.mri_cand_errors_db_obj.insert_mri_candidate_errors(info_to_insert_dict)

    def insert_protocol_violated_scan(self, patient_name, cand_id, psc_id, tarchive_id, scan_param, file_rel_path,
                                      mri_protocol_group_id):
        """
        Insert a row into mri_protocol_violated_scan table.

        :param patient_name: PatientName associated to the file to insert
         :type patient_name: str
        :param cand_id: CandID associated to the file to insert
         :type cand_id: int
        :param psc_id: PSCID associated to the file to insert
         :type psc_id: str
        :param tarchive_id: TarchiveID of the archive the file has been derived from
         :type tarchive_id: int
        :param scan_param: parameters of the image to insert
         :type scan_param: dict
        :param file_rel_path: relative path to the file in trashbin
         :type file_rel_path: str
        :param mri_protocol_group_id: MRIProtocolGroupID of the scan
         :type mri_protocol_group_id: int
        """

        phase_encoding_dir = scan_param["PhaseEncodingDirection"] if "PhaseEncodingDirection" in scan_param else None

        info_to_insert_dict = {
            "CandID": cand_id,
            "PSCID": psc_id,
            "TarchiveID": tarchive_id,
            "time_run": datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            "series_description": scan_param["SeriesDescription"],
            "minc_location": file_rel_path,
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
            "SeriesUID": scan_param["SeriesInstanceUID"] if "SeriesInstanceUID" in scan_param.keys() else None,
            "image_type": str(scan_param["ImageType"]) if "ImageType" in scan_param.keys() else None,
            "PhaseEncodingDirection": phase_encoding_dir,
            "EchoNumber": repr(scan_param["EchoNumber"]) if "EchoNumber" in scan_param else None,
            "MriProtocolGroupID": mri_protocol_group_id if mri_protocol_group_id else None
        }
        self.mri_prot_viol_scan_db_obj.insert_protocol_violated_scans(info_to_insert_dict)

    def insert_mri_violations_log(self, info_to_insert_dict):
        """
        Inserts into mri_violations_log table the entry determined by the information stored in info_to_insert_dict.

        :param info_to_insert_dict: dictionary with the information to be inserted in mri_violations_log
         :type info_to_insert_dict: dict
        """
        self.mri_viol_log_db_obj.insert_violations_log(info_to_insert_dict)

    def get_parameter_type_id(self, parameter_name):
        """
        Greps ParameterTypeID from parameter_type table using parameter_name.
        If no ParameterTypeID were found, will create it in parameter_type.

        :param parameter_name: name of the parameter to look in parameter_type
         :type parameter_name: str

        :return: ParameterTypeID
         :rtype: int
        """

        bids_mapping_dict = self.param_type_db_obj.get_bids_to_minc_mapping_dict()

        param_type_id = self.param_type_db_obj.get_parameter_type_id(param_alias=parameter_name) \
            if parameter_name in bids_mapping_dict.keys() \
            else self.param_type_db_obj.get_parameter_type_id(param_name=parameter_name)

        if not param_type_id:
            # if no parameter type ID found, create an entry in parameter_type
            param_type_id = self.param_type_db_obj.insert_parameter_type(
                {
                    'Name': parameter_name,
                    'Alias': None,
                    'Type': 'text',
                    'Description': f'{parameter_name} magically created by lib.imaging python class',
                    'SourceFrom': 'parameter_file',
                    'Queryable': 0
                }
            )

            # link the newly created parameter_type_id to parameter type category 'MRI Variables'
            category_id = self.param_type_db_obj.get_parameter_type_category_id('MRI Variables')
            self.param_type_db_obj.insert_into_parameter_type_category_rel(category_id, param_type_id)

        return param_type_id

    def get_scan_type_name_from_id(self, scan_type_id):
        """
        Returns the scan type name associated to an acquisition protocol ID.

        :param scan_type_id: acquisition protocol ID
         :type scan_type_id: int

        :return: name of the scan type associated to the scan type ID
         :rtype: str
        """
        return self.mri_scan_type_db_obj.get_scan_type_name_from_id(scan_type_id)

    def get_scan_type_id_from_scan_type_name(self, scan_type_name):
        """
        Returns the acquisition protocol ID associated to a scan type name.

        :param scan_type_name: scan type name
         :type scan_type_name: str

        :return: acquisition protocol ID associated to the scan type name
         :rtype: int
        """
        return self.mri_scan_type_db_obj.get_scan_type_id_from_name(scan_type_name)

    def get_bids_to_minc_terms_mapping(self):
        """
        Returns the BIDS to MINC terms mapping queried from parameter_type table.

        :return: BIDS to MINC terms mapping dictionary
         :rtype: dict
        """
        return self.param_type_db_obj.get_bids_to_minc_mapping_dict()

    def get_list_of_eligible_protocols_based_on_session_info(self, project_id, subproject_id,
                                                             center_id, visit_label, scanner_id):
        """
        Get the list of eligible protocols based on the scan session information.

        :param project_id: ProjectID associated to the scan
         :type project_id: int
        :param subproject_id: SubprojectID associated to the scan
         :type subproject_id: int
        :param center_id: CenterID associated to the scan
         :type center_id: int
        :param visit_label: Visit label associated to the scan
         :type visit_label: str
        :param scanner_id: ID of the scanner associated to the scan
         :type scanner_id: int

        :return: list of eligible protocols
         :rtype: list
        """
        return self.mri_prot_db_obj.get_list_of_protocols_based_on_session_info(
            project_id, subproject_id, center_id, visit_label, scanner_id
        )

    def get_bids_files_info_from_parameter_file_for_file_id(self, file_id):
        """
        Fetch other BIDS files associated to the NIfTI file present in the files table.

        :param file_id: FileID of the NIfTI file in the files table
         :type file_id: int

        """
        return [
            self.grep_parameter_value_from_file_id_and_parameter_name(file_id, "bids_json_file"),
            self.grep_parameter_value_from_file_id_and_parameter_name(file_id, "check_bval_filename"),
            self.grep_parameter_value_from_file_id_and_parameter_name(file_id, "check_bvec_filename")
        ]

    def grep_parameter_value_from_file_id_and_parameter_name(self, file_id, param_type_name):
        """
        Grep a Value in parameter_file based on a FileID and parameter type Name.

        :param file_id: FileID to look for in parameter_file
         :type file_id: int
        :param param_type_name: parameter type Name to use to query parameter_file
         :type param_type_name: str

        :return: value found in the parameter_file table for the FileID and parameter Name
         :rtype: str
        """

        param_type_id = self.get_parameter_type_id(param_type_name)
        if param_type_id:
            return self.param_file_db_obj.get_parameter_file_for_file_id_param_type_id(file_id, param_type_id)

    def grep_file_type_from_file_id(self, file_id):
        """
        Greps the file type stored in the files table using its FileID.

        :param file_id: FileID associated with the file
         :type file_id: int

        :return: file type of the file with FileID
         :rtype: str
        """

        query = "SELECT FileType FROM files WHERE FileID = %s"

        results = self.db.pselect(query=query, args=(file_id,))

        # return the result
        return results[0]['FileType'] if results else None

    def grep_file_path_from_file_id(self, file_id):
        """
        Greps the file path stored in the files table using its FileID.

        :param file_id: FileID associated with the file
         :type file_id: int

        :return: file type of the file with FileID
         :rtype: str
        """

        query = "SELECT File FROM files WHERE FileID = %s"

        results = self.db.pselect(query=query, args=(file_id,))

        # return the result
        return results[0]['File'] if results else None

    def grep_cand_id_from_file_id(self, file_id):
        """
        Greps the CandID using the file's FileID.

        :param file_id: FileID associated with the file
        :type file_id : int

        :return: CandID of the candidate associated to the file
         :rtype: int
        """

        query = "SELECT CandID " + \
                " FROM session s " + \
                " JOIN files f ON (s.ID=f.SessionID) " + \
                " WHERE FileID = %s"

        results = self.db.pselect(query=query, args=(file_id,))

        # return the result
        return results[0]['CandID'] if results else None

    def determine_subject_ids(self, tarchive_info_dict, scanner_id=None):
        """
        Determine subject IDs based on the DICOM header specified by the lookupCenterNameUsing
        config setting. This function will call a function in the config file that can be
        customized for each project.

        :param tarchive_info_dict: dictionary with information about the DICOM archive queried
                                   from the tarchive table
         :type tarchive_info_dict: dict
        :param scanner_id        : ScannerID
         :type scanner_id        : int or None

        :return subject_id_dict: dictionary with subject IDs and visit label or error status
         :rtype subject_id_dict: dict
        """

        config_obj = Config(self.db, self.verbose)
        dicom_header = config_obj.get_config('lookupCenterNameUsing')
        dicom_value = tarchive_info_dict[dicom_header]

        try:
            subject_id_dict = self.config_file.get_subject_ids(self.db, dicom_value, scanner_id)
            subject_id_dict['PatientName'] = dicom_value
        except AttributeError:
            message = 'Config file does not contain a get_subject_ids routine. Upload will exit now.'
            return {'error_message': message}

        return subject_id_dict

    def validate_subject_ids(self, subject_id_dict):
        """
        Ensure that the subject PSCID/CandID corresponds to a single candidate in the candidate
        table and that the visit label can be found in the Visit_Windows table. If those
        conditions are not fulfilled, then a 'CandMismatchError' with the validation error
        is added to the subject IDs dictionary (subject_id_dict).

        :param subject_id_dict : dictionary with subject IDs and visit label
         :type subject_id_dict : dict

        :return: True if the subject IDs are valid, False otherwise
         :rtype: bool
        """

        psc_id = subject_id_dict['PSCID']
        cand_id = subject_id_dict['CandID']
        visit_label = subject_id_dict['visitLabel']
        is_phantom = subject_id_dict['isPhantom']

        # no further checking if the subject is phantom
        if is_phantom:
            return True

        # check that the CandID and PSCID are valid
        # TODO use candidate_db class for that for bids_import
        query = 'SELECT c1.CandID, c2.PSCID AS PSCID ' \
                ' FROM candidate c1 ' \
                ' LEFT JOIN candidate c2 ON (c1.CandID=c2.CandID AND c2.PSCID = %s) ' \
                ' WHERE c1.CandID = %s'
        results = self.db.pselect(query=query, args=(psc_id, cand_id))
        if not results:
            # if no rows were returned, then the CandID is not valid
            subject_id_dict['message'] = '=> Could not find candidate with CandID=' + cand_id \
                                         + ' in the database'
            subject_id_dict['CandMismatchError'] = 'CandID does not exist'
            return False
        elif not results[0]['PSCID']:
            # if no PSCID returned in the row, then PSCID and CandID do not match
            subject_id_dict['message'] = '=> PSCID and CandID of the image mismatch'
            # Message is undefined
            subject_id_dict['CandMismatchError'] = subject_id_dict['message']
            return False

        # check if visit label is valid
        # TODO use visit_windows class for that for bids_import
        query = 'SELECT Visit_label FROM Visit_Windows WHERE BINARY Visit_label = %s'
        results = self.db.pselect(query=query, args=(visit_label,))
        if results:
            subject_id_dict['message'] = f'=> Found visit label {visit_label} in Visit_Windows'
            return True
        elif subject_id_dict['createVisitLabel']:
            subject_id_dict['message'] = f'=> Will create visit label {visit_label} in Visit_Windows'
            return True
        else:
            subject_id_dict['message'] = f'=> Visit Label {visit_label} does not exist in Visit_Windows'
            # Message is undefined
            subject_id_dict['CandMismatchError'] = subject_id_dict['message']
            return False

    def map_bids_param_to_loris_param(self, file_parameters):
        """
        Maps the BIDS parameters found in the BIDS JSON file with the
        parameter type names of LORIS.

        :param file_parameters: dictionary with the list of parameters
                                found in the BIDS JSON file
         :type file_parameters: dict

        :return: returns a dictionary with the BIDS JSON parameter names
                 as well as their LORIS equivalent
         :rtype: dic
        """

        param_type_obj = ParameterType(self.db, self.verbose)
        map_dict = param_type_obj.get_bids_to_minc_mapping_dict()

        # map BIDS parameters with the LORIS ones
        for param in list(file_parameters):
            if param in map_dict.keys():
                file_parameters[map_dict[param]] = file_parameters[param]

        return file_parameters

    def get_acquisition_protocol_info(self, protocols_list, nifti_name, scan_param):
        """
        Get acquisition protocol information (scan_type_id or message to be printed in the log).
        - If the protocols list provided as input is empty, the scan_type_id will be set to None and proper message
        will be returned
        - If no protocol listed in protocols_list matches the parameters of the scan, then the scan_type_id will be set
        to None and proper message will be returned
        - If more than one protocol matches, the scan_type_id will be set to None and proper message will be returned

        :param protocols_list: list of protocols to loop through to find a matching protocol
         :type protocols_list: list
        :param nifti_name: name of the NIfTI file to print in the returned message
         :type nifti_name: str
        :param scan_param: dictionary with the scan parameters to use to determine acquisition protocol
         :type scan_param: dict

        :return: dictionary with 'scan_type_id' and 'message' keys.
         :rtype: dict
        """

        if not len(protocols_list):
            message = f"Warning! No protocol group can be used to determine the scan type of {nifti_name}." \
                      f" Incorrect/incomplete setup of table mri_protocol_group_target."
            return {
                'scan_type_id': None,
                'error_message': message,
                'mri_protocol_group_id': None
            }

        mri_protocol_group_ids = set(map(lambda x: x['MriProtocolGroupID'], protocols_list))
        if len(mri_protocol_group_ids) > 1:
            message = f"Warning! More than one protocol group can be used to identify the scan type of {nifti_name}." \
                      f" Ambiguous setup of table mri_protocol_group_target."
            return {
                'scan_type_id': None,
                'error_message': message,
                'mri_protocol_group_id': None
            }

        # look for matching protocols
        mri_protocol_group_id = protocols_list[0]['MriProtocolGroupID']
        matching_protocols_list = self.look_for_matching_protocols(protocols_list, scan_param)

        # if more than one protocol matching, return False, otherwise, return the scan type ID
        if not matching_protocols_list:
            message = f'Warning! Could not identify protocol of {nifti_name}.'
            return {
                'scan_type_id': None,
                'error_message': message,
                'mri_protocol_group_id': mri_protocol_group_id
            }
        elif len(matching_protocols_list) > 1:
            message = f'Warning! More than one protocol matched the image acquisition parameters of {nifti_name}.'
            return {
                'scan_type_id': None,
                'error_message': message,
                'mri_protocol_group_id': mri_protocol_group_id
            }
        else:
            scan_type_id = matching_protocols_list[0]
            message = f'Acquisition protocol ID for the file to insert is {scan_type_id}'
            return {
                'scan_type_id': scan_type_id,
                'error_message': message,
                'mri_protocol_group_id': mri_protocol_group_id
            }

    def get_bids_categories_mapping_for_scan_type_id(self, scan_type_id):
        """
        Function that get the BIDS information for a given scan type ID from the database and returns a
        dictionary with this information

        :param scan_type_id: scan type ID to use to query the BIDS information for that scan type
         :type scan_type_id: int

        :return: dictionary with the BIDS entities to be associated with that scan type in the future NIfTI file name
         :rtype: dict
        """

        return self.mri_prot_db_obj.get_bids_info_for_scan_type_id(scan_type_id)

    def look_for_matching_protocols(self, protocols_list, scan_param):
        """
        Look for matching protocols in protocols_list given scan parameters stored in scan_param.

        :param protocols_list: list of protocols to evaluate against scan parameters
         :type protocols_list: list
        :param scan_param: scan parameters
         :type scan_param: dict

        :return: list of matching protocols
         :rtype: list
        """

        matching_protocols_list = []
        for protocol in protocols_list:
            if protocol['series_description_regex']:
                if re.search(
                        rf"{protocol['series_description_regex']}", scan_param['SeriesDescription'], re.IGNORECASE
                ):
                    matching_protocols_list.append(protocol['Scan_type'])
            elif self.is_scan_protocol_matching_db_protocol(protocol, scan_param):
                matching_protocols_list.append(protocol['Scan_type'])

        return list(dict.fromkeys(matching_protocols_list))

    def is_scan_protocol_matching_db_protocol(self, db_prot, scan_param):
        """
        Determines if a scan protocol matches a protocol previously taken from the mri_protocol table.

        :param db_prot: database protocol to compare the scan parameters to
         :type db_prot: dict
        :param scan_param: the image protocol
         :type scan_param: dict

        :return: True if the image protocol matches the database protocol, False otherwise
         :rtype: bool
        """

        scan_tr = scan_param['RepetitionTime'] * 1000 if 'RepetitionTime' in scan_param else None
        scan_te = scan_param['EchoTime'] * 1000 if 'EchoTime' in scan_param else None
        scan_ti = scan_param['InversionTime'] * 1000 if 'InversionTime' in scan_param else None
        scan_slice_thick = scan_param['SliceThickness'] if 'SliceThickness' in scan_param else None
        scan_img_type = str(scan_param['ImageType']) if 'ImageType' in scan_param else None
        scan_ped = scan_param['PhaseEncodingDirection'] if 'PhaseEncodingDirection' in scan_param else None
        scan_en = scan_param['EchoNumber'] if 'EchoNumber' in scan_param else None

        if (self.in_range(scan_param['time'], db_prot['time_min'], db_prot['time_max'])) \
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
                and (not db_prot['PhaseEncodingDirection'] or scan_ped == db_prot['PhaseEncodingDirection']) \
                and (not db_prot['EchoNumber'] or scan_en == int(db_prot['EchoNumber'])) \
                and (not db_prot['image_type'] or scan_img_type == db_prot['image_type']):
            return True

    def run_extra_file_checks(self, project_id, subproject_id, visit_label, scan_type_id, scan_param_dict):
        """
        Runs the extra file checks for a given scan type to determine if there are any violations to protocol.

        :param project_id: Project ID associated with the image to be inserted
         :type project_id: int
        :param subproject_id: Subproject ID associated with the image to be inserted
         :type subproject_id: int
        :param visit_label: Visit label associated with the image to be inserted
         :type visit_label: str
        :param scan_type_id: Scan type ID identified for the image to be inserted
         :type scan_type_id: int
        :param scan_param_dict: scan parameters (from the JSON file)
         :type scan_param_dict: dict

        :return: dictionary with two list: one for the 'warning' violations and one for the 'exclude' violations
         :rtype: dict
        """

        # get list of lines in mri_protocol_checks that apply to the given scan based on the protocol group
        checks_list = self.mri_prot_check_db_obj.get_list_of_possible_protocols_based_on_session_info(
            project_id, subproject_id, visit_label, scan_type_id
        )

        distinct_headers = set(map(lambda x: x['Header'], checks_list))
        warning_violations_list = []
        exclude_violations_list = []
        for header in distinct_headers:
            warning_violations = self.get_violations(checks_list, header, 'warning', scan_param_dict)
            exclude_violations = self.get_violations(checks_list, header, 'exclude', scan_param_dict)
            if warning_violations:
                warning_violations_list.append(warning_violations)
            if exclude_violations:
                exclude_violations_list.append(exclude_violations)

        return {
            'warning': warning_violations_list,
            'exclude': exclude_violations_list
        }

    def get_violations(self, checks_list, header, severity, scan_param_dict):
        """
        Get scan violations for a given header and severity.

        :param checks_list:
         :type checks_list: list
        :param header: name of the header to use to check if there is a violation
         :type header: str
        :param severity: severity of the violation (one of 'warning' or 'exclude') in mri_protocol_checks
         :type severity: str
        :param scan_param_dict: image parameters
         :type scan_param_dict: dict

        :return: dictionary with the details regarding the violation (to be inserted in mri_violations_log eventually)
         :rtype: dict
        """

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

        bids_mapping_dict = self.param_type_db_obj.get_bids_to_minc_mapping_dict()
        bids_header = header
        if bids_header not in scan_param_dict.keys():
            # then, the header is a MINC header and needs to be mapped to the BIDS term
            # equivalent to find the value in the JSON file
            for key, val in bids_mapping_dict.items():
                if val == header:
                    bids_header = key
        if bids_header not in scan_param_dict.keys():
            return None
        scan_param = scan_param_dict[bids_header]

        passes_range_check = bool(len([
            True for v in valid_ranges if self.in_range(scan_param, v[0], v[1])]
        )) if valid_ranges else True
        passes_regex_check = bool(len([
            True for r in valid_regexs if re.match(r, scan_param, re.IGNORECASE)
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

    def get_scanner_id(self, manufacturer, software_version, serial_nb, model_name, center_id, project_id):
        """
        Get the scanner ID based on the scanner information provided as input.

        :param manufacturer: Scanner manufacturer
         :type manufacturer: str
        :param software_version: Scanner software version
         :type software_version: str
        :param serial_nb: Scanner serial number
         :type serial_nb: str
        :param model_name: Scanner model name
         :type model_name: str
        :param center_id: ID of the scanner's center
         :type center_id: int
        :param project_id: ID of the scanner's project
         :type project_id: int
        """
        return self.mri_scanner_db_obj.determine_scanner_information(
            manufacturer,
            software_version,
            serial_nb,
            model_name,
            center_id,
            project_id
        )

    def get_scanner_candid(self, scanner_id):
        """
        Select a ScannerID CandID based on the scanner ID in mri_scanner.

        :param scanner_id: scanner ID in the mri_scanner table
         :type scanner_id: int

        :return: scanner CandID
         :rtype: int
        """
        return self.mri_scanner_db_obj.get_scanner_candid(scanner_id)

    def determine_intended_for_field_for_fmap_json_files(self, tarchive_id):
        """
        Determine what should go in the IntendedFor field of the fieldmap's JSON side car file.

        :param tarchive_id: the Tarchive ID to process
         :type tarchive_id: int

        :return: a dictionary with the fieldmap scans dictionary containing JSON file path and intendedFor information
         :rtype: dict
        """

        # get list files from a given tarchive ID
        files_list = self.files_db_obj.get_files_inserted_for_tarchive_id(tarchive_id)

        # get the list of fmap files for which IntendedFor key will be added in the BIDS JSON file
        sorted_fmap_files_dict = self.get_list_of_fmap_files_sorted_by_acq_time(files_list)

        # get the list of files sorted by acquisition time
        sorted_new_files_list = self.get_list_of_files_sorted_by_acq_time(files_list)

        if not sorted_new_files_list or not sorted_fmap_files_dict:
            # if got empty lists, then there are no files to determine IntendedFor either because acq_time
            # was not set or because there are no fieldmap data
            return None

        for key in sorted_fmap_files_dict.keys():
            sorted_fmap_files_list = sorted_fmap_files_dict[key]
            for idx, fmap_dict in enumerate(sorted_fmap_files_list):
                if not fmap_dict['acq_time']:
                    continue
                fmap_acq_time = fmap_dict['acq_time']
                next_fmap_acq_time = sorted_fmap_files_list[idx + 1]['acq_time'] \
                    if idx + 1 < len(sorted_fmap_files_list) else None
                sorted_fmap_files_list[idx]['IntendedFor'] = \
                    self.get_intended_for_list_of_scans_after_fieldmap_acquisition_based_on_acq_time(
                        sorted_new_files_list,
                        fmap_acq_time,
                        next_fmap_acq_time
                )

        return sorted_fmap_files_dict

    def get_list_of_files_already_inserted_for_tarchive_id(self, tarchive_id):
        """
        Get the list of filenames already inserted for a given TarchiveID.

        :param tarchive_id: the Tarchive ID to process
         :type tarchive_id: int

        :return: a list with file names already inserted in the files table for TarchiveID
         :rtype: list
        """

        # get list files from a given tarchive ID
        results = self.files_db_obj.get_files_inserted_for_tarchive_id(tarchive_id)

        files_list = []
        for entry in results:
            files_list.append(os.path.basename(entry['File']))

        return files_list

    def get_list_of_fmap_files_sorted_by_acq_time(self, files_list):
        """
        Get the list of fieldmap acquisitions that requires the IntendedFor field in their JSON file.
        The following BIDS suffix will need that field according to BIDS standards:
          - magnitude, magnitude1, magnitude2
          - phasediff, phase1, phase2
          - fieldmap
          - epi

        :param files_list: a list of dictionaries with all NIfTI files produced for a given tarchive ID
         :type files_list: list

        :return: a dictionary with the dir-AP, dir-PA and no-dir keys listing the different NIfTI files for the tarchive
         :rtype: dict
        """

        # list BIDS fieldmap suffixes to handle
        bids_fmap_suffix_list = ['magnitude', 'magnitude1', 'magnitude2',
                                 'phasediff', 'phase1', 'phase2',
                                 'fieldmap', 'epi']

        fmap_files_dir_ap = []
        fmap_files_dir_pa = []
        fmap_files_no_dir = []
        for file_dict in files_list:

            bids_info = self.mri_prot_db_obj.get_bids_info_for_scan_type_id(
                file_dict['AcquisitionProtocolID']
            )
            param_file_result = self.param_file_db_obj.get_parameter_file_for_file_id_param_type_id(
                file_dict['FileID'],
                self.param_type_db_obj.get_parameter_type_id('acquisition_time')
            )
            acq_time = param_file_result['Value'] if param_file_result else None
            if bids_info['BIDSCategoryName'] == 'fmap' and bids_info['BIDSScanType'] in bids_fmap_suffix_list:
                json_file_path = self.param_file_db_obj.get_parameter_file_for_file_id_param_type_id(
                    file_dict['FileID'],
                    self.param_type_db_obj.get_parameter_type_id('bids_json_file')
                )['Value']
                file_dict = {
                    'FileID': file_dict['FileID'],
                    'FilePath': file_dict['File'],
                    'bids_suffix': bids_info['BIDSScanType'],
                    'bids_subcategory': bids_info['BIDSScanTypeSubCategory'],
                    'json_file_path': json_file_path,
                    'acq_time': acq_time
                }
                if re.match(r'dir-AP', bids_info['BIDSScanTypeSubCategory']):
                    fmap_files_dir_ap.append(file_dict)
                elif re.match(r'dir-PA', bids_info['BIDSScanTypeSubCategory']):
                    fmap_files_dir_pa.append(file_dict)
                else:
                    fmap_files_no_dir.append(file_dict)

        try:
            fmap_files_dict = {
                'dir-AP': sorted(fmap_files_dir_ap, key=lambda x: x['acq_time']),
                'dir-PA': sorted(fmap_files_dir_pa, key=lambda x: x['acq_time']),
                'no-dir': sorted(fmap_files_no_dir, key=lambda x: x['acq_time']),
            }
        except TypeError:
            return None

        return fmap_files_dict

    def get_list_of_files_sorted_by_acq_time(self, files_list):
        """
        Get a sorted list of the NIfTI files that might need fmap correction. That includes files with
          - dwi BIDS subcategory: dwi, sbref
          - func BIDS subcategory: bold, sbref
          - perf BIDS subcategory: asl, sbref
        The returned list will be sorted by acquisition time.

        :param files_list: a list of dictionaries with all NIfTI files produced for a given tarchive ID
         :type files_list: list

        :return: the list of files that might need fmap correction sorted by acquisition time.
         :rtype: list
        """

        # list BIDS dwi, func and perf suffixes to handle
        bids_dwi_suffix_list = ['dwi', 'sbref']
        bids_func_suffix_list = ['bold', 'sbref']
        bids_perf_suffix_list = ['asl', 'sbref']

        new_files_list = []
        for file_dict in files_list:
            bids_info = self.mri_prot_db_obj.get_bids_info_for_scan_type_id(
                file_dict['AcquisitionProtocolID']
            )
            param_file_result = self.param_file_db_obj.get_parameter_file_for_file_id_param_type_id(
                file_dict['FileID'],
                self.param_type_db_obj.get_parameter_type_id('acquisition_time')
            )
            acq_time = param_file_result['Value'] if param_file_result else None
            require_fmap = False
            if (bids_info['BIDSCategoryName'] == 'dwi' and bids_info['BIDSScanType'] in bids_dwi_suffix_list) \
                    or (bids_info['BIDSCategoryName'] == 'func' and bids_info['BIDSScanType'] in bids_func_suffix_list)\
                    or (bids_info['BIDSCategoryName'] == 'perf' and bids_info['BIDSScanType'] in bids_perf_suffix_list):
                require_fmap = True

            bids_visit_label = os.path.split(os.path.split(os.path.dirname(file_dict['File']))[0])[1]
            nii_rel_file_path = os.path.join(
                bids_visit_label,
                bids_info['BIDSCategoryName'],
                os.path.basename(file_dict['File'])
            )

            new_files_list.append({
                'FileID': file_dict['FileID'],
                'BidsFileRelPath': nii_rel_file_path,
                'bids_suffix': bids_info['BIDSScanType'],
                'bids_subcategory': bids_info['BIDSScanTypeSubCategory'],
                'acq_time': acq_time,
                'need_fmap': require_fmap
            })

        try:
            sorted_files_list = sorted(new_files_list, key=lambda x: x['acq_time'])
        except TypeError:
            return None
        
        return sorted_files_list

    def modify_fmap_json_file_to_write_intended_for(self, sorted_fmap_files_list, s3_obj, tmp_dir):
        """
        Function that reads the JSON file and modifies it to add the BIDS IntendedFor field to it.

        :param sorted_fmap_files_list: list of dictionary that contains JSON file path info and IntendedFor content
         :type sorted_fmap_files_list: list
        :param s3_obj: S3 object for downloading and uploading of S3 files
         :type s3_obj: AWS object
        :param tmp_dir: temporary directory where to download JSON file if file is on S3
         :type tmp_dir: str
        """

        for fmap_dict in sorted_fmap_files_list:
            if 'IntendedFor' not in fmap_dict:
                continue
            json_file_path = ''
            if fmap_dict['json_file_path'].startswith('s3://'):
                try:
                    json_file_path = os.path.join(tmp_dir, os.path.basename(fmap_dict['json_file_path']))
                    s3_obj.download_file(fmap_dict['json_file_path'], json_file_path)
                except Exception as err:
                    print(err)
                    continue
            else:
                data_dir = self.config_db_obj.get_config('dataDirBasepath')
                json_file_path = os.path.join(data_dir, fmap_dict['json_file_path'])

            with open(json_file_path) as json_file:
                json_data = json.load(json_file)
            json_data['IntendedFor'] = fmap_dict['IntendedFor']
            with open(json_file_path, 'w') as json_file:
                json_file.write(json.dumps(json_data, indent=4))
            json_blake2 = blake2b(json_file_path.encode('utf-8')).hexdigest()
            param_type_id = self.param_type_db_obj.get_parameter_type_id('bids_json_file_blake2b_hash')
            param_file_dict = self.param_file_db_obj.get_parameter_file_for_file_id_param_type_id(
                fmap_dict['FileID'],
                param_type_id
            )
            self.param_file_db_obj.update_parameter_file(json_blake2, param_file_dict['ParameterFileID'])

            if fmap_dict['json_file_path'].startswith('s3://'):
                try:
                    s3_obj.upload_file(json_file_path, fmap_dict['json_file_path'])
                except Exception as err:
                    print(err)
                    continue

    @staticmethod
    def get_intended_for_list_of_scans_after_fieldmap_acquisition_based_on_acq_time(files_list, current_fmap_acq_time,
                                                                                    next_fmap_acq_time):
        """
        Determine the list files to add to the IntendedFor field of the current JSON fieldmap examined.
        The matching files will be the ones acquired after the current fieldmap examined and before the next
        fieldmap examined.

        :param files_list: list of files to loop through
         :type files_list: list
        :param current_fmap_acq_time: the acquisition time of the fieldmap for which IntendedFor is generated
         :type current_fmap_acq_time: str
        :param next_fmap_acq_time: the acquisition of the next fieldmap
         :type next_fmap_acq_time: str

        :return: content of the IntendedFor array to be added to the fieldmap JSON file
         :rtype: list
        """

        # find acquisitions closest to the acq_time of the fmap after the fmap acquisition
        intended_for = []
        for file_dict in files_list:
            if not file_dict['acq_time']:
                continue
            nii_file_acq = file_dict['acq_time']
            if not file_dict['need_fmap']:
                continue
            if nii_file_acq <= current_fmap_acq_time:
                # ignore if nii acquisition preceded fmap acquisition
                continue
            if next_fmap_acq_time and nii_file_acq >= next_fmap_acq_time:
                # ignore if nii acquisition happened after the next fmap acq
                continue
            intended_for.append(file_dict['BidsFileRelPath'])

        return intended_for

    @staticmethod
    def extract_files_from_dicom_archive(dicom_archive_path, extract_location_dir):
        """
        Extracts a DICOM archive into a directory.

        :param dicom_archive_path: path to the DICOM archive file
         :type dicom_archive_path: str
        :param extract_location_dir: location directory where the archive should be extracted
         :type extract_location_dir: str

        :return: path to the directory with the extracted DICOM files
         :rtype: str
        """
        tar = tarfile.open(dicom_archive_path)
        tar.extractall(path=extract_location_dir)
        inner_tar_file_name = [f.name for f in tar.getmembers() if f.name.endswith('.tar.gz')][0]
        tar.close()

        inner_tar_path = os.path.join(extract_location_dir, inner_tar_file_name)
        inner_tar = tarfile.open(inner_tar_path)
        inner_tar.extractall(path=extract_location_dir)
        inner_tar.close()

        extracted_dicom_dir_path = inner_tar_path.replace(".tar.gz", "")
        return extracted_dicom_dir_path

    @staticmethod
    def create_imaging_pic(file_info, pic_rel_path=None):
        """
        Creates the preview pic that will show in the imaging browser view session
        page. This pic will be stored in the data_dir/pic folder

        :param file_info: dictionary with file information (path, file_id, cand_id...)
         :type file_info: dict
        :param pic_rel_path: relative path to the pic to use if one provided. Otherwise
                             create_imaging_pic will automatically generate the pic name
                             based on the file path of the NIfTI file
         :type pic_rel_path: str

        :return: path to the created pic
         :rtype: str
        """

        cand_id = file_info['cand_id']
        file_path = os.path.join(file_info['data_dir_path'], file_info['file_rel_path'])
        is_4d_data = file_info['is_4D_dataset']
        file_id = file_info['file_id']

        pic_name = os.path.basename(file_path)
        pic_name = re.sub(r"\.nii(\.gz)?$", f'_{str(file_id)}_check.png', pic_name)
        pic_rel_path = os.path.join(str(cand_id), pic_name)

        # create the candID directory where the pic will go if it does not already exist
        pic_dir = os.path.join(file_info['data_dir_path'], 'pic', str(cand_id))
        if not os.path.exists(pic_dir):
            os.mkdir(pic_dir)

        volume = image.index_img(file_path, 0) if is_4d_data else file_path

        plotting.plot_anat(
            anat_img=volume,
            output_file=os.path.join(file_info['data_dir_path'], 'pic', pic_rel_path),
            display_mode='ortho',
            black_bg=1,
            draw_cross=0,
            annotate=0
        )

        return pic_rel_path

    @staticmethod
    def get_nifti_image_length_parameters(nifti_filepath):
        """
        Get the NIfTI image length dimensions (x, y, z and time for 4D dataset).

        :param nifti_filepath: path to the NIfTI file
         :type nifti_filepath: str

        :return: tuple with the length of each dimension of the NIfTI file
         :rtype: tuple
        """

        img = nib.load(nifti_filepath)

        # get the voxel/time length array of the image
        length = img.shape

        return length

    @staticmethod
    def get_nifti_image_step_parameters(nifti_filepath):
        """
        Get the NIfTI image step information (xstep, ystep, zstep and number of volumes
        for 4D dataset)

        :param nifti_filepath: path to the NIfTI file
         :type nifti_filepath: str

        :return: tuple with the step information for the NIfTI file
         :rtype: tuple
        """

        img = nib.load(nifti_filepath)

        # get the voxel step/time step of the image
        step = img.header.get_zooms()

        return step

    @staticmethod
    def in_range(value, field_min, field_max):
        """
        Determine if a value falls into a min and max range.

        :param value: value to evaluate
         :type value: float or int
        :param field_min: minimal range value
         :type field_min: float or int
        :param field_max: maximal range value
         :type field_max: float or int

        :return: True if the value falls into the range, False otherwise
         :rtype: bool
        """

        # return True when parameter min and max values are not defined (a.k.a. no restrictions in mri_protocol)
        if not field_min and not field_max:
            return True

        # return False if value is not defined since this field is listed as a restriction in mri_protocol
        # (a.k.a. passed the first if)
        if not value:
            return False

        # return True if min & max are defined and value is within the range
        if field_min and field_max and float(field_min) <= float(value) <= float(field_max):
            return True

        # return True if only min is defined and value is <= min
        if field_min and not field_max and float(field_min) <= float(value):
            return True

        # return True if only max is defined and value is >= max
        if field_max and not field_min and float(value) <= float(field_max):
            return True

        # if we got this far, then value is out of range
        return False

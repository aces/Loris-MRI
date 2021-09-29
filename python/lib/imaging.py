"""This class performs database queries and common imaging checks (MRI...)"""

import os
import datetime
import nibabel as nib
import re

from nilearn import image, plotting

import lib.exitcode
from lib.database_lib.site import Site
from lib.database_lib.config import Config
from lib.database_lib.files import Files
from lib.database_lib.mri_scanner import MriScanner
from lib.database_lib.mri_protocol_checks import MriProtocolChecks
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
        self.files_db_obj = Files(db, verbose)
        self.mri_prot_check_db_obj = MriProtocolChecks(db, verbose)
        self.mri_scanner_db_obj = MriScanner(db, verbose)
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

    def grep_file_info_from_series_uid_and_echo_time(self, series_uid, echo_time):
        """
        Greps the file ID from the files table. If it cannot be found, the method will return None.

        :param series_uid: Series Instance UID of the file to look for
         :type series_uid: str
        :param echo_time: Echo Time of the file to look for
         :type echo_time: str

        :return: dictionary with files table content of the found file
        :rtype: dict
        """
        return self.files_db_obj.find_file_with_series_uid_and_echo_time(series_uid, echo_time)

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
            if type(value) == list:
                if type(value[0]) in [float, int]:
                    parameter_file_data_dict[key] = [str(f) for f in parameter_file_data_dict[key]]
                parameter_file_data_dict[key] = f"[{', '.join(parameter_file_data_dict[key])}]"
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

        # Gather column name & values to insert into parameter_file
        param_type_id = self.get_parameter_type_id(parameter_name)
        param_file_insert_info_dict = {
            'ParameterTypeID': param_type_id,
            'FileID': file_id,
            'Value': value,
            'InsertTime': datetime.datetime.now().timestamp()
        }
        self.param_file_db_obj.insert_parameter_file(param_file_insert_info_dict)

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
            if parameter_name in bids_mapping_dict.values() \
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

    def grep_parameter_value_from_file_id(self, file_id, param_name):
        """
        Greps the value stored in physiological_parameter_file for a given
        PhysiologicalFileID and parameter name (from the parameter_type table).

        :param file_id   : FileID to use in the query
         :type file_id   : int
        :param param_name: parameter name to use in the query
         :type param_name: str

        :return: result of the query from the parameter_file table
         :rtype: dict
        """

        query = "SELECT Value " \
                "FROM parameter_file " \
                "JOIN parameter_type USING (ParameterTypeID) " \
                "WHERE FileID = %s AND Name = %s"

        results = self.db.pselect(
            query=query,
            args=(file_id, param_name)
        )

        # return the result
        return results[0] if results else None

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
                " FROM session s " +\
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
            message = 'ERROR: config file does not contain a get_subject_ids routine.' \
                      ' Upload will exit now.'
            return {
                'error': True,
                'exit_code': lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE,
                'message': message
            }

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

    def determine_study_center(self, tarchive_info_dict):
        """
        Determine the study center associated to the DICOM archive based on a DICOM header
        specified by the lookupCenterNameUsing config setting.

        :param tarchive_info_dict: dictionary with information about the DICOM archive queried
                                   from the tarchive table
         :type tarchive_info_dict: dict

        :return: dictionary with CenterName and CenterID information
         :rtype: dict
        """

        subject_id_dict = self.determine_subject_ids(tarchive_info_dict)
        if 'error' in subject_id_dict.keys():
            # subject_id_dict contain the error, exit code and message to explain the error
            return subject_id_dict

        cand_id = subject_id_dict['CandID']
        visit_label = subject_id_dict['visitLabel']
        patient_name = subject_id_dict['PatientName']

        # get the CenterID from the session table if the PSCID and visit label exists
        # and could be extracted from the database
        if cand_id and visit_label:
            query = 'SELECT s.CenterID AS CenterID, p.MRI_alias AS CenterName' \
                    ' FROM session s' \
                    ' JOIN psc p ON p.CenterID=s.CenterID' \
                    ' WHERE s.CandID = %s AND s.Visit_label = %s'
            results = self.db.pselect(query=query, args=(cand_id, visit_label))
            if results:
                return results[0]

        # if could not find center information based on cand_id and visit_label, use the
        # patient name to match it to the site alias or MRI alias
        site = Site(self.db, self.verbose)
        list_of_sites = site.get_list_of_sites()
        for site_dict in list_of_sites:
            if site_dict['Alias'] in patient_name:
                return {'CenterName': site_dict['Alias'], 'CenterID': site_dict['CenterID']}
            elif site_dict['MRI_alias'] in patient_name:
                return {'CenterName': site_dict['MRI_alias'], 'CenterID': site_dict['CenterID']}

        # if we got here, it means we could not find a center associated to the dataset
        return {
            'error': True,
            'exit_code': lib.exitcode.SELECT_FAILURE,
            'message': 'ERROR: No center found for this DICOM study'
        }

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

        scan_tr = scan_param['RepetitionTime'] * 1000
        scan_te = scan_param['EchoTime'] * 1000
        scan_ti = scan_param['InversionTime'] * 1000

        scan_slice_thick = scan_param['SliceThickness']
        scan_img_type = scan_param['ImageType']
        # TODO handle image type: note: img_type = ["ORIGINAL", "PRIMARY", "M", "ND", "NORM"] in JSON
        if ("time" not in scan_param or self.in_range(scan_param['time'], db_prot['time_min'], db_prot['time_max'])) \
                and self.in_range(scan_tr,              db_prot['TR_min'],     db_prot['TR_max']) \
                and self.in_range(scan_te,              db_prot['TE_min'],     db_prot['TE_max']) \
                and self.in_range(scan_ti,              db_prot['TI_min'],     db_prot['TI_max']) \
                and self.in_range(scan_param['xstep'],  db_prot['xstep_min'],  db_prot['xstep_max']) \
                and self.in_range(scan_param['ystep'],  db_prot['ystep_min'],  db_prot['ystep_max']) \
                and self.in_range(scan_param['zstep'],  db_prot['zstep_min'],  db_prot['zstep_max']) \
                and self.in_range(scan_param['xspace'], db_prot['xspace_min'], db_prot['xspace_max']) \
                and self.in_range(scan_param['yspace'], db_prot['yspace_min'], db_prot['yspace_max']) \
                and self.in_range(scan_param['zspace'], db_prot['zspace_min'], db_prot['zspace_max']) \
                and self.in_range(scan_slice_thick,     db_prot['slice_thickness_min'], db_prot['slice_thickness_max'])\
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
            bids_header = [k for k, v in bids_mapping_dict.items() if v == header][0]
        scan_param = scan_param_dict[bids_header]

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

    def get_scanner_id_from_json_data(self, scan_param_dict, center_id):

        scanner_id = self.mri_scanner_db_obj.determine_scanner_information(
            scan_param_dict["Manufacturer"],
            scan_param_dict["SoftwareVersions"],
            scan_param_dict["DeviceSerialNumber"],
            scan_param_dict["ManufacturersModelName"],
            center_id
        )


    @staticmethod
    def create_imaging_pic(file_info):
        """
        Creates the preview pic that will show in the imaging browser view session
        page. This pic will be stored in the data_dir/pic folder

        :param file_info: dictionary with file information (path, file_id, cand_id...)
         :type file_info: dict

        :return: path to the created pic
         :rtype: str
        """

        cand_id = file_info['cand_id']
        file_path = file_info['data_dir_path'] + file_info['file_rel_path']
        is_4d_data = file_info['is_4D_dataset']
        file_id = file_info['file_id']

        pic_name = os.path.basename(file_path)
        pic_name = re.sub(r"\.nii(\.gz)", '_' + str(file_id) + '_check.png', pic_name)
        pic_rel_path = str(cand_id) + '/' + pic_name

        # create the candID directory where the pic will go if it does not already exist
        pic_dir = file_info['data_dir_path'] + 'pic/' + str(cand_id)
        if not os.path.exists(pic_dir):
            os.mkdir(pic_dir)

        volume = image.index_img(file_path, 0) if is_4d_data else file_path

        plotting.plot_anat(
            anat_img=volume,
            output_file=file_info['data_dir_path'] + 'pic/' + pic_rel_path,
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

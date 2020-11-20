"""This class performs database queries and common imaging checks (MRI...)"""

import sys
import re
import os
import datetime
import subprocess
import nilearn
import numpy   as np
import nibabel as nib

from nilearn import plotting
from nilearn import image

import lib.exitcode
from lib.candidate import Candidate
from lib.database_lib.site import Site

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

        self.db          = db
        self.verbose     = verbose
        self.config_file = config_file

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

        imaging_file_types = self.db.pselect(
            query="SELECT type FROM ImagingFileTypes"
        )

        # if the file type cannot be found in the database, exit now
        file_type = None
        for type in imaging_file_types:
            regex_match = r'' + type['type'] + r'(\.gz)?$'
            if re.search(regex_match, file):
                file_type = type['type']

        # exits if could not find a file type
        if not file_type:
            message = "\nERROR: File type for " + file + " does not exist " \
                      "in ImagingFileTypes database table\n"
            print(message)
            sys.exit(lib.exitcode.SELECT_FAILURE)

        return file_type

    def grep_file_id_from_hash(self, blake2b_hash):
        """
        Greps the file ID from the files table. If it cannot be found, the method ]
        will return None.

        :param blake2b_hash: blake2b hash
         :type blake2b_hash: str

        :return: file ID and file path
         :rtype: int
        """

        query = "SELECT f.FileID, f.File "     \
                "FROM files AS f "     \
                "JOIN parameter_file " \
                    "USING (FileID) "   \
                "JOIN parameter_type "               \
                    "USING (ParameterTypeID) "       \
                "WHERE Value=%s"

        results = self.db.pselect(query=query, args=(blake2b_hash,))

        # return the results
        return results[0] if results else None

    def insert_imaging_file(self, file_info, file_data):
        """
        Inserts the imaging file and its information into the files and parameter_file tables.

        :param file_info: dictionary with values to insert into files' table
         :type file_info: dict
        :param file_data: dictionary with values to insert into parameter_file's table
         :type file_data: dict

        :return: file ID
         :rtype: int
        """

        # insert info from file_info into files
        file_fields = ()
        file_values = ()
        for key, value in file_info.items():
            file_fields = file_fields + (key,)
            file_values = file_values + (value,)
        file_id = self.db.insert(
            table_name='files',
            column_names=file_fields,
            values=[file_values],
            get_last_id=True
        )

        # insert info from file_data into parameter_file
        for key, value in file_data.items():
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
        unix_timestamp    = datetime.datetime.now().strftime("%s")
        parameter_type_id = self.get_parameter_type_id(parameter_name)
        parameter_file_fields = ('FileID', 'ParameterTypeID', 'Value',    'InsertTime')
        parameter_file_values = (file_id,  parameter_type_id, str(value), unix_timestamp)
        self.db.insert(
            table_name='parameter_file',
            column_names=parameter_file_fields,
            values=parameter_file_values
        )

    def get_parameter_type_id(self, parameter_name):
        """
        Greps ParameterTypeID from parameter_type table using parameter_name.
        If no ParameterTypeID were found, will create it in parameter_type.

        :param parameter_name: name of the parameter to look in parameter_type
         :type parameter_name: str

        :return: ParameterTypeID
         :rtype: int
        """

        results = self.db.pselect(
            query="SELECT ParameterTypeID "
                  "FROM parameter_type "   
                  "WHERE Name = %s "
                  "AND SourceFrom='parameter_file'",
            args=(parameter_name,)
        )

        if results:
            # if results, grep the parameter_type_id
            parameter_type_id = results[0]['ParameterTypeID']
        else:
            # if no results, create an entry in parameter_type
            col_names = (
                'Name', 'Type', 'Description', 'SourceFrom', 'Queryable'
            )
            parameter_desc = parameter_name + " magically created by" \
                             " lib.imaging python class"
            source_from    = 'parameter_file'
            values = (
                parameter_name, 'text', parameter_desc, source_from, 0
            )
            parameter_type_id = self.db.insert(
                table_name   = 'parameter_type',
                column_names = col_names,
                values       = values,
                get_last_id  = True
            )

            # link the parameter_type_id to a parameter type category
            category_id = self.get_parameter_type_category_id()
            self.db.insert(
                table_name   = 'parameter_type_category_rel',
                column_names = ('ParameterTypeCategoryID', 'ParameterTypeID'),
                values       = (category_id, parameter_type_id),
                get_last_id  = False
            )

        return parameter_type_id

    def get_parameter_type_category_id(self):
        """
        Greps ParameterTypeCategoryID from parameter_type_category table.
        If no ParameterTypeCategoryID was found, it will return None.

        :return: ParameterTypeCategoryID
         :rtype: int
        """

        category_result = self.db.pselect(
            query='SELECT ParameterTypeCategoryID '
                  'FROM parameter_type_category '
                  'WHERE Name = %s ',
            args=('MRI Variables',)
        )

        if not category_result:
            return None

        return category_result[0]['ParameterTypeCategoryID']

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
            query = query,
            args  = (file_id, param_name)
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

        dicom_header = self.db.get_config('lookupCenterNameUsing')
        dicom_value  = tarchive_info_dict[dicom_header]

        try:
            subject_id_dict = self.config_file.get_subject_ids(self.db, dicom_value, scanner_id)
            subject_id_dict['PatientName'] = dicom_value
        except AttributeError:
            message = 'ERROR: config file does not contain a get_subject_ids routine.' \
                      ' Upload will exit now.'
            return {
                'error'     : True,
                'exit_code' : lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE,
                'message'   : message
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

        psc_id      = subject_id_dict['PSCID']
        cand_id     = subject_id_dict['CandID']
        visit_label = subject_id_dict['visitLabel']
        is_phantom  = subject_id_dict['isPhantom']

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
            subject_id_dict['CandMismatchError'] = message
            return False

        # check if visit label is valid
        query   = 'SELECT Visit_label FROM Visit_Windows WHERE BINARY Visit_label = %s'
        results = self.db.pselect(query=query, args=(visit_label,))
        if results:
            subject_id_dict['message'] = "=> Found visit label " + visit_label + 'in Visit_Windows'
            return True
        elif subject_id_dict['createVisitLabel']:
            subject_id_dict['message'] = '=> Will create visit label ' + visit_label \
                                         + 'in Visit_Windows'
            return True
        else:
            subject_id_dict['message'] = '=> Visit Label ' + visit_label \
                                         + ' does not exist in Visit_Windows'
            subject_id_dict['CandMismatchError'] = message
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

        cand_id         = subject_id_dict['CandID']
        visit_label     = subject_id_dict['visitLabel']
        patient_name    = subject_id_dict['PatientName']

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
            'error'    : True,
            'exit_code': lib.exitcode.SELECT_FAILURE,
            'message'  : 'ERROR: No center found for this DICOM study'
        }

    @staticmethod
    def map_bids_param_to_loris_param(file_parameters):
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

        map_dict = {
            'manufacturersModelName'      : 'manufacturer_model_name',
            'DeviceSerialNumber'          : 'device_serial_number',
            'SoftwareVersions'            : 'software_versions',
            'MagneticFieldStrength'       : 'magnetic_field_strength',
            'ReceiveCoilName'             : 'receiving_coil',
            'ScanningSequence'            : 'scanning_sequence',
            'SequenceVariant'             : 'sequence_variant',
            'SequenceName'                : 'sequence_name',
            'PhaseEncodingDirection'      : 'phase_encoding_direction',
            'EchoTime'                    : 'echo_time',
            'RepetitionTime'              : 'repetition_time',
            'InversionTime'               : 'inversion_time',
            'SliceThickness'              : 'slice_thickness',
            'InstitutionName'             : 'institution_name',
            'ImageType'                   : 'image_type',
            'AcquisitionTime'             : 'acquisition_time',
            'AcquisitionMatrixPE'         : 'acquisition_matrix',
            'PercentPhaseFOV'             : 'percent_phase_field_of_view',
            'ImageOrientationPatientDICOM': 'image_orientation_patient',
            'MRAcquisitionType'           : 'mr_acquisition_type',
            'AcquisitionNumber'           : 'acquisition_number',
            'PatientPosition'             : 'patient_position',
            'ImagingFrequency'            : 'imaging_frequency',
            'SeriesNumber'                : 'series_number',
            'PixelBandwidth'              : 'pixel_bandwidth',
            'SeriesDescription'           : 'series_description',
            'ProtocolName'                : 'protocol_name',
            'SpacingBetweenSlices'        : 'spacing_between_slices',
            'NumberOfAverages'            : 'number_of_averages',
        }

        # map BIDS parameters with the LORIS ones
        for param in list(file_parameters):
            if param in map_dict.keys():
                file_parameters[map_dict[param]] = file_parameters[param]

        return file_parameters

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

        cand_id    = file_info['cand_id']
        file_path  = file_info['data_dir_path'] + file_info['file_rel_path']
        is_4d_data = file_info['is_4D_dataset']
        file_id    = file_info['file_id']

        pic_name     = os.path.basename(file_path)
        pic_name     = re.sub(r"\.nii(\.gz)", '_' + str(file_id) + '_check.png', pic_name)
        pic_rel_path = str(cand_id) + '/' + pic_name

        # create the candID directory where the pic will go if it does not already exist
        pic_dir = file_info['data_dir_path'] + 'pic/' + str(cand_id)
        if not os.path.exists(pic_dir):
            os.mkdir(pic_dir)

        volume = image.index_img(file_path, 0) if is_4d_data else file_path

        nilearn.plotting.plot_anat(
            anat_img     = volume,
            output_file  = file_info['data_dir_path'] + 'pic/' + pic_rel_path,
            display_mode = 'ortho',
            black_bg     = 1,
            draw_cross   = 0,
            annotate     = 0
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

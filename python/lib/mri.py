"""Deals with MRI BIDS datasets and register them into the database."""

import os
import json
import getpass
import string
from pyblake2 import blake2b

import lib.exitcode
import lib.utilities as utilities
from lib.database   import Database
from lib.candidate  import Candidate
from lib.session    import Session
from lib.imaging    import Imaging
from lib.bidsreader import BidsReader
from lib.scanstsv   import ScansTSV


__license__ = "GPLv3"


class Mri:

    def __init__(self, bids_reader, bids_sub_id, bids_ses_id, bids_modality, db,
                 verbose, data_dir, default_visit_label,
                 loris_bids_mri_rel_dir, loris_bids_root_dir):

        # enumerate the different suffixes supported by BIDS per modality type
        self.possible_suffix_per_modality = {
            'anat' : [
                       'T1w',   'T2w', 'T1rho', 'T1map', 'T2map',     'T2star',    'FLAIR',
                       'FLASH', 'PD',  'PDmap', 'PDT2',  'inplaneT1', 'inplaneT2', 'angio'
                     ],
            'func' : [
                       'bold', 'cbv', 'phase'
                     ],
            'dwi'  : [
                       'dwi', 'sbref'
                     ],
            'fmap' : [
                       'phasediff', 'magnitude1', 'magnitude2', 'phase1', 'phase2',
                       'fieldmap', 'epi'
                     ]
        }

        # load bids objects
        self.bids_reader = bids_reader
        self.bids_layout = bids_reader.bids_layout

        # load the LORIS BIDS import root directory where the files will be copied
        self.loris_bids_mri_rel_dir = loris_bids_mri_rel_dir
        self.loris_bids_root_dir    = loris_bids_root_dir
        self.data_dir               = data_dir

        # load BIDS subject, visit and modality
        self.bids_sub_id   = bids_sub_id
        self.bids_ses_id   = bids_ses_id
        self.bids_modality = bids_modality

        # load database handler object and verbose bool
        self.db      = db
        self.verbose = verbose

        # find corresponding CandID and SessionID in LORIS
        self.loris_cand_info = self.get_loris_cand_info()
        self.default_vl      = default_visit_label
        self.psc_id          = self.loris_cand_info['PSCID']
        self.cand_id         = self.loris_cand_info['CandID']
        self.center_id       = self.loris_cand_info['RegistrationCenterID']
        self.session_id      = self.get_loris_session_id()

        # grep all the NIfTI files for the modality
        self.nifti_files = self.grep_nifti_files()

        # check if a tsv with acquisition dates or age is available for the subject
        self.scans_file = None
        if self.bids_layout.get(suffix='scans', subject=self.psc_id, return_type='filename'):
            self.scans_file = \
            self.bids_layout.get(suffix='scans', subject=self.psc_id, return_type='filename')[0]

        # loop through NIfTI files and register them in the DB
        for nifti_file in self.nifti_files:
            self.register_nifti_file(nifti_file)


    def get_loris_cand_info(self):
        """
        Gets the LORIS Candidate info for the BIDS subject.

        :return: Candidate info of the subject found in the database
         :rtype: list
        """

        candidate       = Candidate(verbose=self.verbose, psc_id=self.bids_sub_id)
        loris_cand_info = candidate.get_candidate_info_from_loris(self.db)

        return loris_cand_info

    def get_loris_session_id(self):
        """
        Greps the LORIS session.ID corresponding to the BIDS visit. Note,
        if no BIDS visit are set, will use the default visit label value set
        in the config module

        :return: the session's ID in LORIS
         :rtype: int
        """

        # check if there are any visit label in BIDS structure, if not,
        # will use the default visit label set in the config module
        visit_label = self.bids_ses_id if self.bids_ses_id else self.default_vl

        session = Session(
            verbose     = self.verbose,
            cand_id     = self.cand_id,
            center_id   = self.center_id,
            visit_label = visit_label
        )
        loris_vl_info = session.get_session_info_from_loris(self.db)

        if not loris_vl_info:
            message = "ERROR: visit label " + visit_label + "does not exist in " + \
                      "the session table for candidate "  + self.cand_id         + \
                      "\nPlease make sure the visit label is created in the "    + \
                      "database or run bids_import.py with the -s option -s if " + \
                      "you wish that the insertion pipeline creates the visit "  + \
                      "label in the session table."
            print(message)
            exit(lib.exitcode.SELECT_FAILURE)

        return loris_vl_info['ID']

    def grep_nifti_files(self):
        """
        Returns the list of NIfTI files found for the modality.

        :return: list of NIfTI files found for the modality
         :rtype: list
        """

        # grep all the possible suffixes for the modality
        modality_possible_suffix = self.possible_suffix_per_modality[modality]

        # loop through the possible suffixes and grep the NIfTI files
        nii_files_list = {}
        for suffix in modality_possible_suffix:
            nii_files_list.extend(self.grep_bids_files(suffix, 'nii.gz'))

        # return the list of found NIfTI files
        return nii_files_list

    def grep_bids_files(self, bids_type, extension):
        """
        Greps the BIDS files and their layout information from the BIDSLayout
        and return that list.

        :param bids_type: the BIDS type to use to grep files (events,
                          channels, eeg, electrodes)
         :type bids_type: str
        :param extension: extension of the file to look for (nii.gz, json...)
         :type extension: str

        :return: list of files from the BIDS layout
         :rtype: list
        """

        if self.bids_ses_id:
            return self.bids_layout.get(
                subject     = self.bids_sub_id,
                session     = self.bids_ses_id,
                datatype    = self.bids_modality,
                extension   = extension,
                suffix      = bids_type
            )
        else:
            return self.bids_layout.get(
                subject     = self.bids_sub_id,
                datatype    = self.bids_modality,
                extension   = extension,
                suffix      = bids_type
            )

    def register_raw_file(self, nifti_file):

        # insert the NIfTI file
        inserted_nii  = self.fetch_and_insert_nifti_file(nifti_file)


    def fetch_and_insert_nifti_file(self, nifti_file, derivatives=None):

        # load the Imaging object that will be used to insert the imaging data into the database
        imaging = Imaging(self.db, self.verbose)

        # load the list of associated files with the NIfTI file
        associated_files = nifti_file.get_associations()

        # load the entity information from the NIfTI file
        entities  = nifti_file.get_entities()
        scan_type = entities['suffix']
        run       = entities['run']
        task      = entities['task']
        acq       = entities['acquisition']
        dir       = entities['dir']

        # loop through the associated files to grep JSON, bval, bvec...
        json_file = None
        other_assoc_files = {}
        for assoc_file in associated_files:
            file_info = assoc_file.get_entities()
            if file_info['extension'] == 'json':
                json_file = assoc_file.path
            elif file_info['extension'] == 'bvec':
                other_assoc_files['bvec_file'] = assoc_file.path
            elif file_info['extension'] == 'bval':
                other_assoc_files['bval_file'] = assoc_file.path
            elif file_info['extension'] == 'tsv' and file_info['suffix'] == 'events':
                other_assoc_files['task_file'] = assoc_file.path
            elif file_info['extension'] == 'tsv' and file_info['suffix'] == 'physio':
                other_assoc_files['physio_file'] = assoc_file.path

        # read the json file if it exists
        file_parameters = {}
        if json_file:
            with open(json_file) as data_file:
                file_parameters = json.load(data_file)
            # copy the JSON file to the LORIS BIDS import directory
            json_path = self.copy_file_to_loris_bids_dir(json_file)
            file_parameters['bids_json_file'] = json_path
            json_blake2 = blake2b(json_file.encode('utf-8')).hexdigest()
            file_parameters['bids_json_file_blake2b_hash'] = json_blake2

        # grep the file type from the ImagingFileTypes table
        file_type = imaging.determine_file_type(nifti_file.filename)

        # determine the output type
        output_type = 'derivatives' if derivatives else 'raw'

        # get the acquisition date of the MRI file or the age at the time of the MRI acquisition
        if self.scans_file:
            scan_info = ScansTSV(self.scans_file, ni_file, self.verbose)
            file_parameters['scan_acquisition_time'] = scan_info.get_acquisition_time()
            file_parameters['age_at_scan'] = scan_info.get_age_at_scan()
            # copy the scans.tsv file to the LORIS BIDS import directory
            scans_path = scan_info.copy_scans_tsv_file_to_loris_bids_dir(
                self.bids_sub_id, self.loris_bids_root_dir, self.data_dir
            )
            file_parameters['scans_tsv_file'] = scans_path
            scans_blake2 = blake2b(self.scans_file.encode('utf-8')).hexdigest()
            file_parameters['scans_tsv_file_bake2hash'] = scans_blake2

        # add all other associated files to the file_parameters so they get inserted
        # in parameter_file
        for type in other_assoc_files:
            original_file_path = other_assoc_files[type]
            copied_path = self.copy_file_to_loris_bids_dir(original_file_path)
            file_param_name  = 'bids' + type
            file_parameters[param_name] = copied_path
            file_blake2 = blake2b(original_file_path.encode('utf-8')).hexdigest()
            hash_param_name = file_param_name + '_blake2b_hash'
            file_parameters[hash_param_name] = file_blake2

        # append the blake2b to the MRI file parameters dictionary
        blake2 = blake2b(eeg_file.encode('utf-8')).hexdigest()
        file_parameters['file_blake2b_hash'] = blake2

        # check that the file using blake2b is not already inserted before inserting it
        result    = imaging.grep_file_id_from_hash(blake2)
        file_id   = result['FileID'] if result else None
        file_path = result['File']   if result else None
        if not file_id:
            # grep the scan type ID from the mri_scan_type table
            scan_type_id = self.db.grep_id_from_lookup_table(
                id_field_name       = 'ID',
                table_name          = 'mri_scan_type',
                where_field_name    = 'Scan_type',
                where_value         = scan_type,
                insert_if_not_found = False
            )

            # copy the eeg_file to the LORIS BIDS import directory
            file_path = self.copy_file_to_loris_bids_dir(nifti_file.path)

            # insert the file along with its information into files and parameter_file tables
            file_info = {
                'FileType'       : file_type,
                'File'           : file_path,
                'SessionID'      : self.session_id,
                'InsertedByUser' : getpass.getuser(),
                'OutputType'     : output_type,
                'AcquisitionProtocolID': scan_type_id
            }
            file_id = imaging.insert_imaging_file(file_info, file_parameters)

        return {'file_id': file_id, 'file_path': file_path}

    def copy_file_to_loris_bids_dir(self, file, derivatives_path=None):
        """
        Wrapper around the utilities.copy_file function that copies the file
        to the LORIS BIDS import directory and returns the relative path of the
        file (without the data_dir part).

        :param file: full path to the original file
         :type file: str
        :param derivatives_path: path to the derivative folder
         :type derivatives_path: str

        :return: relative path to the copied file
         :rtype: str
        """

        # determine the path of the copied file
        copy_file = self.loris_bids_eeg_rel_dir
        if self.bids_ses_id:
            copy_file += os.path.basename(file)
        else:
            # make sure the ses- is included in the new filename if using
            # default visit label from the LORIS config
            copy_file += str.replace(
                os.path.basename(file),
                "sub-" + self.bids_sub_id,
                "sub-" + self.bids_sub_id + "_ses-" + self.default_vl
            )
        if derivatives_path:
            # create derivative subject/vl/modality directory
            lib.utilities.create_dir(
                derivatives_path + self.loris_bids_eeg_rel_dir,
                self.verbose
            )
            copy_file = derivatives_path + copy_file
        else:
            copy_file = self.loris_bids_root_dir + copy_file

        # copy the file
        utilities.copy_file(file, copy_file, self.verbose)

        # determine the relative path and return it
        relative_path = copy_file.replace(self.data_dir, "")

        return relative_path
"""Deals with MRI BIDS datasets and register them into the database."""

import json
import os
import re
from typing import Any

from bids.layout import BIDSFile

import lib.exitcode
from lib.bidsreader import BidsReader
from lib.db.models.session import DbSession
from lib.db.queries.file import try_get_file_with_hash
from lib.env import Env
from lib.imaging_lib.bids import determine_bids_file_type
from lib.imaging_lib.file import register_imaging_file
from lib.imaging_lib.file_parameter import register_file_parameter, register_file_parameters
from lib.imaging_lib.nifti import get_nifti_image_length_parameters, get_nifti_image_step_parameters
from lib.imaging_lib.nifti_pic import create_imaging_pic
from lib.imaging_lib.scan_type import get_or_create_scan_type
from lib.import_bids_dataset.imaging import map_bids_param_to_loris_param
from lib.logging import log_error_exit
from lib.scanstsv import ScansTSV
from lib.util.crypto import compute_file_blake2b_hash
from lib.util.fs import copy_file


class Mri:
    """
    This class reads the BIDS MRI data structure and registers the MRI datasets into the
    database by calling lib.imaging class.

    :Example:

        from lib.bidsreader import BidsReader
        from lib.mri        import Mri
        from lib.database   import Database

        # database connection
        db = Database(config_file.mysql, verbose)
        db.connect()

        # grep config settings from the Config module
        config_obj      = Config(db, verbose)
        default_bids_vl = config_obj.get_config('default_bids_vl')
        data_dir        = config_obj.get_config('dataDirBasepath')

        # load the BIDS directory
        bids_reader = BidsReader(bids_dir)

        # create the LORIS_BIDS directory in data_dir based on Name and BIDS version
        loris_bids_root_dir = create_loris_bids_directory(
            bids_reader, data_dir, verbose
        )
        for row in bids_reader.cand_session_modalities_list:
            for modality in row['modalities']:
                if modality in ['anat', 'dwi', 'fmap', 'func']:
                    bids_session = row['bids_ses_id']
                    visit_label = bids_session if bids_session else default_bids_vl
                    loris_bids_mri_rel_dir = "sub-" + row['bids_sub_id'] + "/" + \
                                             "ses-" + visit_label + "/mri/"
                    lib.utilities.create_dir(
                        loris_bids_root_dir + loris_bids_mri_rel_dir, verbose
                    )
                    Eeg(
                        bids_reader   = bids_reader,
                        bids_sub_id   = row['bids_sub_id'],
                        bids_ses_id   = row['bids_ses_id'],
                        bids_modality = modality,
                        db            = db,
                        verbose       = verbose,
                        data_dir      = data_dir,
                        default_visit_label    = default_bids_vl,
                        loris_bids_eeg_rel_dir = loris_bids_mri_rel_dir,
                        loris_bids_root_dir    = loris_bids_root_dir
                    )

        # disconnect from the database
        db.disconnect()
    """

    def __init__(
        self, env: Env, session: DbSession, bids_reader: BidsReader, bids_sub_id: str, bids_ses_id: str | None,
        bids_modality: str, data_dir: str, loris_bids_mri_rel_dir: str, loris_bids_root_dir : str | None,
    ):
        self.env = env

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

        # find corresponding CandID and SessionID in LORIS
        self.session = session

        # grep all the NIfTI files for the modality
        self.nifti_files = self.grep_nifti_files()

        # check if a tsv with acquisition dates or age is available for the subject
        self.scans_file = None
        if self.bids_layout.get(suffix='scans', subject=self.bids_sub_id, return_type='filename'):
            self.scans_file = self.bids_layout.get(suffix='scans', subject=self.bids_sub_id,
                                                   return_type='filename', extension='tsv')[0]

        # loop through NIfTI files and register them in the DB
        for nifti_file in self.nifti_files:
            self.register_raw_file(nifti_file)

    def grep_nifti_files(self) -> list[BIDSFile]:
        """
        Returns the list of NIfTI files found for the modality.

        :return: list of NIfTI files found for the modality
        """

        # grep all the possible suffixes for the modality
        modality_possible_suffix = self.possible_suffix_per_modality[self.bids_modality]

        # loop through the possible suffixes and grep the NIfTI files
        nii_files_list = []
        for suffix in modality_possible_suffix:
            nii_files_list.extend(self.grep_bids_files(suffix, 'nii.gz'))

        # return the list of found NIfTI files
        return nii_files_list

    def grep_bids_files(self, bids_type: str, extension: str) -> list[BIDSFile]:
        """
        Greps the BIDS files and their layout information from the BIDSLayout
        and return that list.

        :param bids_type: the BIDS type to use to grep files (T1w, T2w, bold, dwi...)
        :param extension: extension of the file to look for (nii.gz, json...)

        :return: list of files from the BIDS layout
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

    def register_raw_file(self, nifti_file: BIDSFile):
        """
        Registers raw MRI files and related files into the files and parameter_file tables.

        :param nifti_file: NIfTI file object
        """

        # insert the NIfTI file
        self.fetch_and_insert_nifti_file(nifti_file)

    def fetch_and_insert_nifti_file(self, nifti_file: BIDSFile):
        """
        Gather NIfTI file information to insert into the files and parameter_file tables.
        Once all the information has been gathered, it will call imaging.insert_imaging_file
        that will perform the insertion into the files and parameter_file tables.
        """

        # load the list of associated files with the NIfTI file
        associated_files = nifti_file.get_associations()

        # load the entity information from the NIfTI file
        entities  = nifti_file.get_entities()
        scan_type = entities['suffix']

        # loop through the associated files to grep JSON, bval, bvec...
        json_file = None
        other_assoc_files = {}
        for assoc_file in associated_files:
            file_info = assoc_file.get_entities()
            if re.search(r'json$', file_info['extension']):
                json_file = assoc_file.path
            elif re.search(r'bvec$', file_info['extension']):
                other_assoc_files['bvec_file'] = assoc_file.path
            elif re.search(r'bval$', file_info['extension']):
                other_assoc_files['bval_file'] = assoc_file.path
            elif re.search(r'tsv$', file_info['extension']) and file_info['suffix'] == 'events':
                other_assoc_files['task_file'] = assoc_file.path
            elif re.search(r'tsv$', file_info['extension']) and file_info['suffix'] == 'physio':
                other_assoc_files['physio_file'] = assoc_file.path

        # read the json file if it exists
        file_parameters: dict[str, Any] = {}
        if json_file:
            with open(json_file) as data_file:
                file_parameters = json.load(data_file)
                map_bids_param_to_loris_param(self.env, file_parameters)
            # copy the JSON file to the LORIS BIDS import directory
            json_path = self.copy_file_to_loris_bids_dir(json_file)
            file_parameters['bids_json_file'] = json_path
            json_blake2 = compute_file_blake2b_hash(json_file)
            file_parameters['bids_json_file_blake2b_hash'] = json_blake2

        # grep the file type from the ImagingFileTypes table
        file_type = determine_bids_file_type(self.env, nifti_file.filename)
        if file_type is None:
            log_error_exit(
                self.env,
                f"File type for {nifti_file.filename} does not exist in ImagingFileTypes database table.",
                lib.exitcode.SELECT_FAILURE,
            )

        # get the acquisition date of the MRI or the age at the time of acquisition
        if self.scans_file:
            scan_info = ScansTSV(self.scans_file, nifti_file.filename, self.env.verbose)
            file_parameters['scan_acquisition_time'] = scan_info.get_acquisition_time()
            file_parameters['age_at_scan'] = scan_info.get_age_at_scan()
            # copy the scans.tsv file to the LORIS BIDS import directory
            scans_path = scan_info.copy_scans_tsv_file_to_loris_bids_dir(
                self.bids_sub_id, self.loris_bids_root_dir, self.data_dir
            )
            file_parameters['scans_tsv_file'] = scans_path
            scans_blake2 = compute_file_blake2b_hash(self.scans_file)
            file_parameters['scans_tsv_file_bake2hash'] = scans_blake2

        # grep voxel step from the NIfTI file header
        step_params = get_nifti_image_step_parameters(nifti_file.path)
        file_parameters['xstep'] = step_params.x_step
        file_parameters['ystep'] = step_params.y_step
        file_parameters['zstep'] = step_params.z_step

        # grep the time length from the NIfTI file header
        length_params = get_nifti_image_length_parameters(nifti_file.path)
        if length_params.time is not None:
            file_parameters['time'] = length_params.time
            is_4d_dataset = True
        else:
            is_4d_dataset = False

        # add all other associated files to the file_parameters so they get inserted
        # in parameter_file
        for type in other_assoc_files:
            original_file_path = other_assoc_files[type]
            copied_path = self.copy_file_to_loris_bids_dir(original_file_path)
            file_param_name = 'bids_' + type
            file_parameters[file_param_name] = copied_path
            file_blake2 = compute_file_blake2b_hash(original_file_path)
            hash_param_name = file_param_name + '_blake2b_hash'
            file_parameters[hash_param_name] = file_blake2

        # append the blake2b to the MRI file parameters dictionary
        blake2 = compute_file_blake2b_hash(nifti_file.path)
        file_parameters['file_blake2b_hash'] = blake2

        # check that the file is not already inserted before inserting it
        file = try_get_file_with_hash(self.env.db, blake2)
        if file is not None:
            return

        # grep the scan type ID from the mri_scan_type table (if it is not already in
        # the table, it will add a row to the mri_scan_type table)
        mri_scan_type = get_or_create_scan_type(self.env, scan_type)

        # copy the NIfTI file to the LORIS BIDS import directory
        file_path = self.copy_file_to_loris_bids_dir(nifti_file.path)

        # insert the file along with its information into files and parameter_file tables
        echo_time                = file_parameters.get('EchoTime')
        echo_number              = file_parameters.get('EchoNumber')
        phase_encoding_direction = file_parameters.get('PhaseEncodingDirection')

        file = register_imaging_file(
            self.env,
            file_type,
            file_path,
            self.session,
            mri_scan_type,
            echo_time,
            echo_number,
            phase_encoding_direction,
        )

        register_file_parameters(self.env, file, file_parameters)

        # create the pic associated with the file
        pic_rel_path = create_imaging_pic(self.env, file, is_4d_dataset)

        if os.path.exists(os.path.join(self.data_dir, 'pic', pic_rel_path)):
            register_file_parameter(self.env, file, 'check_pic_filename', pic_rel_path)

    def copy_file_to_loris_bids_dir(self, file):
        """
        Wrapper around the utilities.copy_file function that copies the file
        to the LORIS BIDS import directory and returns the relative path of the
        file (without the data_dir part).

        :param file: full path to the original file
         :type file: str

        :return: relative path to the copied file
         :rtype: str
        """

        # determine the path of the copied file
        if self.bids_ses_id:
            final_file_rel_path = os.path.join(self.loris_bids_mri_rel_dir, os.path.basename(file))
        else:
            # make sure the ses- is included in the new filename if using
            # default visit label from the LORIS config
            final_file_rel_path = os.path.join(
                self.loris_bids_mri_rel_dir,
                str.replace(
                    os.path.basename(file),
                    f"sub-{self.bids_sub_id}",
                    f"sub-{self.bids_sub_id}_ses-{self.session.visit_label}"
                )
            )

        final_file_path = os.path.join(self.loris_bids_root_dir, final_file_rel_path)

        # copy the file
        copy_file(self.env, file, final_file_path)

        return final_file_rel_path

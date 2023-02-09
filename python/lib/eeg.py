"""Deals with EEG BIDS datasets and register them into the database."""

import os
import json
import getpass
from pyblake2 import blake2b

import lib.exitcode
import lib.utilities as utilities
from lib.candidate                                   import Candidate
from lib.session                                     import Session
from lib.physiological                               import Physiological
from lib.scanstsv                                    import ScansTSV
from lib.database_lib.physiologicalannotationfile    import PhysiologicalAnnotationFile
from lib.database_lib.physiologicalannotationarchive import PhysiologicalAnnotationArchive
from lib.database_lib.physiologicalannotationrel     import PhysiologicalAnnotationRel
from lib.database_lib.physiologicaleventfile         import PhysiologicalEventFile
from lib.database_lib.physiologicaleventarchive      import PhysiologicalEventArchive


__license__ = "GPLv3"


class Eeg:
    """
    This class reads the BIDS EEG data structure and register the EEG datasets
    into the database by calling the lib.physiological class.

    :Example:

        from lib.bidsreader import BidsReader
        from lib.eeg        import Eeg
        from lib.database   import Database
        from lib.database_lib.config import Config

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
                if modality == 'eeg':
                    bids_session = row['bids_ses_id']
                    visit_label = bids_session if bids_session else default_bids_vl
                    loris_bids_eeg_rel_dir = "sub-" + row['bids_sub_id'] + "/" + \
                                             "ses-" + visit_label + "/eeg/"
                    lib.utilities.create_dir(
                        loris_bids_root_dir + loris_bids_eeg_rel_dir, verbose
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
                        loris_bids_eeg_rel_dir = loris_bids_eeg_rel_dir,
                        loris_bids_root_dir    = loris_bids_root_dir
                    )

        # disconnect from the database
        db.disconnect()
    """

    def __init__(self, bids_reader, bids_sub_id, bids_ses_id, bids_modality, db,
                 verbose, data_dir, default_visit_label,
                 loris_bids_eeg_rel_dir, loris_bids_root_dir):
        """
        Constructor method for the Eeg class.

        :param bids_reader  : dictionary with BIDS reader information
         :type bids_reader  : dict
        :param bids_sub_id  : BIDS subject ID (that will be used as PSCID)
         :type bids_sub_id  : str
        :param bids_ses_id  : BIDS session ID (that will be used for the visit label)
         :type bids_ses_id  : str
        :param bids_modality: BIDS modality (a.k.a. EEG)
         :tyoe bids_modality: str
        :param db           : Database class object
         :type db           : object
        :param verbose      : whether to be verbose
         :type verbose      : bool
        :param data_dir     : LORIS data directory path (usually /data/PROJECT/data)
         :type data_dir     : str
        :param default_visit_label   : default visit label to be used if no BIDS
                                       session are present in the BIDS structure
         :type default_visit_label   : str
        :param loris_bids_eeg_rel_dir: LORIS BIDS EEG relative dir path to data_dir
         :type loris_bids_eeg_rel_dir: str
        :param loris_bids_root_dir   : LORIS BIDS root directory path
         :type loris_bids_root_dir   : str
        """

        # load bids objects
        self.bids_reader   = bids_reader
        self.bids_layout   = bids_reader.bids_layout

        # load the LORIS BIDS import root directory where the eeg files will
        # be copied
        self.loris_bids_eeg_rel_dir = loris_bids_eeg_rel_dir
        self.loris_bids_root_dir    = loris_bids_root_dir
        self.data_dir               = data_dir

        # load bids subject, visit and modality
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
        self.project_id      = self.loris_cand_info['RegistrationProjectID']

        self.cohort_id   = None
        for row in bids_reader.participants_info:
            if not row['participant_id'] == self.psc_id:
                continue
            # TODO: change subproject -> cohort in participants.tsv?
            if 'subproject' in row:
                cohort_info = db.pselect(
                    "SELECT CohortID FROM cohort WHERE title = %s",
                    # TODO: change subproject -> cohort in participants.tsv?
                    [row['subproject'], ]
                )
                if len(cohort_info) > 0:
                    self.cohort_id = cohort_info[0]['CohortID']
            break

        self.session_id      = self.get_loris_session_id()
        self.annotations_files = self.grep_bids_files('annotations')

        # check if a tsv with acquisition dates or age is available for the subject
        self.scans_file = None
        if self.bids_layout.get(suffix='scans', subject=self.psc_id, return_type='filename'):
            self.scans_file = self.bids_layout.get(suffix='scans', subject=self.psc_id, return_type='filename')[0]

        # register the data into LORIS
        self.register_data()
        self.register_data(derivatives=True)

    def get_loris_cand_info(self):
        """
        Gets the LORIS Candidate info for the BIDS subject.

        :return: Candidate info of the subject found in the database
         :rtype: list
        """

        candidate = Candidate(verbose=self.verbose, psc_id=self.bids_sub_id)
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
            self.db, self.verbose, self.cand_id, visit_label,
            self.center_id, self.project_id, self.cohort_id
        )
        loris_vl_info = session.get_session_info_from_loris()

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

    def grep_bids_files(self, bids_type):
        """
        Greps the BIDS files and their layout information from the BIDSLayout
        and return that list.

        :param bids_type: the BIDS type to use to grep files (events,
                          channels, eeg, electrodes, annotations)
         :type bids_type: str

        :return: list of files from the BIDS layout
         :rtype: list
        """

        if self.bids_ses_id:
            return self.bids_layout.get(
                subject     = self.bids_sub_id,
                session     = self.bids_ses_id,
                datatype    = self.bids_modality,
                suffix      = bids_type,
                return_type = 'filename'
            )
        else:
            return self.bids_layout.get(
                subject     = self.bids_sub_id,
                datatype    = self.bids_modality,
                suffix      = bids_type,
                return_type = 'filename'
            )

    def register_data(self, derivatives=False):
        """
        Registers raw and derivatives EEG data and related files into the following tables:
            - physiological_file
            - physiological_parameter_file
            - physiological_electrode
            - physiological_channel
            - physiological_task_event
            - physiological_annotation_*

        :param derivatives: True if the EEG file to insert is a derivative file.
                            Set by default to False when inserting raw file.
         :type derivatives: boolean
        """

        # insert EEG file
        inserted_eegs = self.fetch_and_insert_eeg_files(derivatives)

        if not inserted_eegs:
            return

        physiological = Physiological(self.db, self.verbose)

        for inserted_eeg in inserted_eegs:
            eeg_file_id        = inserted_eeg['file_id']
            eeg_file_path      = inserted_eeg['file_path']
            eegjson_file_path  = inserted_eeg['eegjson_file_path']
            fdt_file_path      = inserted_eeg['fdt_file_path']
            original_file_data = inserted_eeg['original_file_data']

            # insert related electrode, channel and event information
            electrode_file_path = self.fetch_and_insert_electrode_file(
                eeg_file_id,
                original_file_data.path,
                derivatives
            )

            channel_file_path = self.fetch_and_insert_channel_file(
                eeg_file_id,
                original_file_data.path,
                derivatives
            )

            event_file_paths = self.fetch_and_insert_event_files(
                eeg_file_id,
                original_file_data.path,
                derivatives
            )

            annotation_file_paths = self.fetch_and_insert_annotation_files(
                eeg_file_id,
                original_file_data.path,
                derivatives
            )

            # archive all files in a tar ball for downloading all files at once
            files_to_archive = (os.path.join(self.data_dir, eeg_file_path),)

            if eegjson_file_path:
                files_to_archive = files_to_archive + (os.path.join(self.data_dir, eegjson_file_path),)
            if fdt_file_path:
                files_to_archive = files_to_archive + (os.path.join(self.data_dir, fdt_file_path),)
            if electrode_file_path:
                files_to_archive = files_to_archive + (os.path.join(self.data_dir, electrode_file_path),)
            if event_file_paths:
                # archive all event files in a tar ball for event download
                event_files_to_archive = ()

                for event_file_path in event_file_paths:
                    files_to_archive = files_to_archive + (os.path.join(self.data_dir, event_file_path),)
                    event_files_to_archive = event_files_to_archive + (
                        os.path.join(self.data_dir, event_file_path),
                    )

                event_archive_rel_name = os.path.splitext(event_file_paths[0])[0] + ".tgz"
                self.create_and_insert_event_archive(
                    event_files_to_archive, event_archive_rel_name, eeg_file_id
                )
            if annotation_file_paths:
                # archive all annotation files in a tar ball for annotation download
                annotation_files_to_archive = ()

                for annotation_file_path in annotation_file_paths:
                    files_to_archive = files_to_archive + (os.path.join(self.data_dir, annotation_file_path),)
                    annotation_files_to_archive = annotation_files_to_archive + (
                        os.path.join(self.data_dir, annotation_file_path),
                    )

                annotation_archive_rel_name = os.path.splitext(annotation_file_path)[0] + ".tgz"
                self.create_and_insert_annotation_archive(
                    annotation_files_to_archive, annotation_archive_rel_name, eeg_file_id
                )
            if channel_file_path:
                files_to_archive = files_to_archive + (os.path.join(self.data_dir, channel_file_path),)

            archive_rel_name = os.path.splitext(eeg_file_path)[0] + ".tgz"
            self.create_and_insert_archive(
                files_to_archive, archive_rel_name, eeg_file_id
            )

            # create data chunks for React visualization in
            # data_dir/bids_import/bids_dataset_name_BIDSVersion_chunks directory
            physiological.create_chunks_for_visualization(eeg_file_id, self.data_dir)

    def fetch_and_insert_eeg_files(self, derivatives=False):
        """
        Gather EEG file information to insert into physiological_file and
        physiological_parameter_file. Once all the information has been
        gathered, it will call self.insert_physiological_file that will
        perform the insertion into physiological_file and
        physiological_parameter_file.

        :param derivatives: True if the EEG file to insert is a derivative file.
                            Set by default to False when inserting raw file.
         :type derivatives: boolean
        :return: dictionary with registered file ID and path to its file
         :rtype: dict
        """

        inserted_eegs = []
        # load the Physiological object that will be used to insert the
        # physiological data into the database
        physiological = Physiological(self.db, self.verbose)

        # TODO if derivatives, grep the source file as well as the input file ID???

        # grep the raw files
        eeg_files = self.bids_layout.get(
            subject   = self.bids_sub_id,
            session   = self.bids_ses_id,
            scope     = 'derivatives' if derivatives else 'raw',
            # datatype  = self.bids_modality,
            suffix    = self.bids_modality,
            extension = ['set', 'edf', 'vhdr', 'vmrk', 'eeg', 'bdf']
        )

        # return if no eeg_file was found
        if not eeg_files:
            return None

        for eeg_file in eeg_files:
            eegjson_file = self.bids_layout.get_nearest(
                eeg_file.path,
                return_type = 'tuple',
                strict=False,
                extension = 'json',
                suffix = self.bids_modality,
                all_ = False,
                full_search = False,
            )

            fdt_file = self.bids_layout.get_nearest(
                eeg_file.path,
                return_type = 'tuple',
                strict=False,
                extension = 'fdt',
                all_ = False,
                full_search = False,
            )

            # read the json file if it exists
            eeg_file_data = {}
            eegjson_file_path = None
            if eegjson_file:
                with open(eegjson_file.path) as data_file:
                    eeg_file_data = json.load(data_file)
                # copy the JSON file to the LORIS BIDS import directory
                eegjson_file_path = self.copy_file_to_loris_bids_dir(
                    eegjson_file.path, derivatives
                )
                eeg_file_data['eegjson_file'] = eegjson_file_path
                json_blake2 = blake2b(eegjson_file.path.encode('utf-8')).hexdigest()
                eeg_file_data['physiological_json_file_blake2b_hash'] = json_blake2

            # greps the file type from the ImagingFileTypes table
            file_type = physiological.determine_file_type(eeg_file.path)

            # grep the output type from the physiological_output_type table
            output_type = 'derivative' if derivatives else 'raw'
            output_type_id = self.db.grep_id_from_lookup_table(
                id_field_name       = 'PhysiologicalOutputTypeID',
                table_name          = 'physiological_output_type',
                where_field_name    = 'OutputTypeName',
                where_value         = output_type,
                insert_if_not_found = False
            )

            # get the acquisition date of the EEG file or the age at the time of the EEG recording
            eeg_acq_time = None
            if self.scans_file:
                scan_info = ScansTSV(self.scans_file, eeg_file.path, self.verbose)
                eeg_acq_time = scan_info.get_acquisition_time()
                eeg_file_data['age_at_scan'] = scan_info.get_age_at_scan()

                # copy the scans.tsv file to the LORIS BIDS import directory
                scans_path = scan_info.copy_scans_tsv_file_to_loris_bids_dir(
                    self.bids_sub_id, self.loris_bids_root_dir, self.data_dir
                )

                eeg_file_data['scans_tsv_file'] = scans_path
                scans_blake2 = blake2b(self.scans_file.encode('utf-8')).hexdigest()
                eeg_file_data['physiological_scans_tsv_file_bake2hash'] = scans_blake2

            # if file type is set and fdt file exists, append fdt path to the
            # eeg_file_data dictionary
            fdt_file_path = None
            if file_type == 'set' and fdt_file:
                # copy the fdt file to the LORIS BIDS import directory
                fdt_file_path = self.copy_file_to_loris_bids_dir(
                    fdt_file.path, derivatives
                )

                eeg_file_data['fdt_file'] = fdt_file_path
                fdt_blake2 = blake2b(fdt_file.path.encode('utf-8')).hexdigest()
                eeg_file_data['physiological_fdt_file_blake2b_hash'] = fdt_blake2

            # append the blake2b to the eeg_file_data dictionary
            blake2 = blake2b(eeg_file.path.encode('utf-8')).hexdigest()
            eeg_file_data['physiological_file_blake2b_hash'] = blake2

            # check that the file using blake2b is not already inserted before
            # inserting it
            result         = physiological.grep_file_id_from_hash(blake2)
            physio_file_id = result['PhysiologicalFileID'] if result else None
            eeg_path       = result['FilePath']            if result else None
            if not physio_file_id:
                # grep the modality ID from physiological_modality table
                modality_id = self.db.grep_id_from_lookup_table(
                    id_field_name       = 'PhysiologicalModalityID',
                    table_name          = 'physiological_modality',
                    where_field_name    = 'PhysiologicalModality',
                    where_value         = self.bids_modality,
                    insert_if_not_found = False
                )

                # copy the eeg_file to the LORIS BIDS import directory
                eeg_path = self.copy_file_to_loris_bids_dir(
                    eeg_file.path, derivatives
                )

                # insert the file along with its information into
                # physiological_file and physiological_parameter_file tables
                eeg_file_info = {
                    'FileType'       : file_type,
                    'FilePath'       : eeg_path,
                    'SessionID'      : self.session_id,
                    'AcquisitionTime': eeg_acq_time,
                    'InsertedByUser' : getpass.getuser(),
                    'PhysiologicalOutputTypeID': output_type_id,
                    'PhysiologicalModalityID'  : modality_id
                }
                physio_file_id = physiological.insert_physiological_file(
                    eeg_file_info, eeg_file_data
                )

            # if the EEG file was a set file, then update the filename for the .set
            # and .fdt files in the .set file so it can find the proper file for
            # visualization and analyses
            if file_type == 'set':
                set_full_path = os.path.join(self.data_dir, eeg_path)
                fdt_full_path = eeg_file_data['fdt_file'] if 'fdt_file' in eeg_file_data.keys() else None

                if fdt_full_path:
                    fdt_full_path = os.path.join(self.data_dir, eeg_file_data['fdt_file'])
                utilities.update_set_file_path_info(set_full_path, fdt_full_path)

            inserted_eegs.append({
                'file_id': physio_file_id,
                'file_path': eeg_path,
                'eegjson_file_path': eegjson_file_path,
                'fdt_file_path': fdt_file_path,
                'original_file_data': eeg_file,
            })

        return inserted_eegs

    def fetch_and_insert_electrode_file(
            self, physiological_file_id, original_physiological_file_path, derivatives=False):
        """
        Gather electrode file information to insert into
        physiological_electrode. Once all the information has been gathered,
        it will call Physiological.insert_electrode_file that will perform the
        insertion into physiological_electrode, linking it to the
        PhysiologicalFileID already registered.

        :param physiological_file_id: PhysiologicalFileID of the associated
                                      physiological file already inserted into
                                      the physiological_file table
         :type physiological_file_id: int
        :param derivatives: True if the electrode file to insert is a derivative file.
                            Set by default to False when inserting raw file.
         :type derivatives: boolean

        :return: electrode file path in the /DATA_DIR/bids_import directory
         :rtype: str
        """

        # load the Physiological object that will be used to insert the
        # physiological data into the database
        physiological = Physiological(self.db, self.verbose)

        electrode_file = self.bids_layout.get_nearest(
            original_physiological_file_path,
            return_type = 'tuple',
            strict = False,
            extension = 'tsv',
            suffix = 'electrodes',
            all_ = False,
            full_search = False,
        )

        if not electrode_file:
            message = "WARNING: no electrode file associated with " \
                      "physiological file ID " + str(physiological_file_id)
            print(message)
            return None
        else:
            result = physiological.grep_electrode_from_physiological_file_id(
                physiological_file_id
            )
            electrode_path = result[0]['FilePath'] if result else None
            electrode_data = utilities.read_tsv_file(electrode_file.path)
            if not result:
                # copy the electrode file to the LORIS BIDS import directory
                electrode_path = self.copy_file_to_loris_bids_dir(
                    electrode_file.path, derivatives
                )
                # get the blake2b hash of the electrode file
                blake2 = blake2b(electrode_file.path.encode('utf-8')).hexdigest()
                # insert the electrode data in the database
                physiological.insert_electrode_file(
                    electrode_data, electrode_path, physiological_file_id, blake2
                )

        return electrode_path

    def fetch_and_insert_channel_file(
            self, physiological_file_id, original_physiological_file_path, derivatives=False):
        """
        Gather channel file information to insert into physiological_channel.
        Once all the information has been gathered, it will call
        Physiological.insert_channel_file that will perform the insertion into
        physiological_channel, linking it to the PhysiologicalFileID already
        registered.

        :param physiological_file_id:            PhysiologicalFileID of the associated
                                                 physiological file already inserted into
                                                 the physiological_file table
         :type physiological_file_id:            int
        :param original_physiological_file_path: path of the original physiological file
         :type original_file_data:               string
        :param derivatives:                      True if the channel file to insert is a derivative file.
                                                 Set by default to False when inserting raw file.
         :type derivatives:                      boolean

        :return: channel file path in the /DATA_DIR/bids_import directory
         :rtype: str
        """

        # load the Physiological object that will be used to insert the
        # physiological data into the database
        physiological = Physiological(self.db, self.verbose)

        channel_file = self.bids_layout.get_nearest(
            original_physiological_file_path,
            return_type = 'tuple',
            strict = False,
            extension = 'tsv',
            suffix = 'channels',
            all_ = False,
            full_search = False,
        )

        if not channel_file:
            message = "WARNING: no channel file associated with " \
                      "physiological file ID " + str(physiological_file_id)
            print(message)
            return None
        else:
            result = physiological.grep_channel_from_physiological_file_id(
                physiological_file_id
            )
            channel_path = result[0]['FilePath'] if result else None
            channel_data = utilities.read_tsv_file(channel_file.path)
            if not result:
                # copy the channel file to the LORIS BIDS import directory
                channel_path = self.copy_file_to_loris_bids_dir(
                    channel_file.path, derivatives
                )
                # get the blake2b hash of the channel file
                blake2 = blake2b(channel_file.path.encode('utf-8')).hexdigest()
                # insert the channel data in the database
                physiological.insert_channel_file(
                    channel_data, channel_path, physiological_file_id, blake2
                )

        return channel_path

    def fetch_and_insert_event_files(
            self, physiological_file_id, original_physiological_file_path, derivatives=False):
        """
        Gather raw channel file information to insert into
        physiological_task_event. Once all the information has been gathered,
        it will call Physiological.insert_event_file that will perform the
        insertion into physiological_task_event, linking it to the
        PhysiologicalFileID already registered.

        :param physiological_file_id:            PhysiologicalFileID of the associated
                                                 physiological file already inserted into
                                                 the physiological_file table
         :type physiological_file_id:            int
        :param original_physiological_file_path: path of the original physiological file
         :type original_file_data:               string
        :param derivatives:                      True if the event file to insert is a derivative file.
                                                 Set by default to False when inserting raw file.
         :type derivatives:                      boolean

        :return: channel file path in the /DATA_DIR/bids_import directory
         :rtype: str
        """

        # load the Physiological object that will be used to insert the
        # physiological data into the database
        physiological = Physiological(self.db, self.verbose)

        event_data_file = self.bids_layout.get_nearest(
            original_physiological_file_path,
            return_type = 'tuple',
            strict = False,
            extension = 'tsv',
            suffix = 'events',
            all_ = False,
            full_search = False,
        )

        if not event_data_file:
            message = "WARNING: no events file associated with " \
                      "physiological file ID " + str(physiological_file_id)
            print(message)
            return None
        else:
            physiological_event_file_obj = PhysiologicalEventFile(self.db, self.verbose)
            event_paths = physiological_event_file_obj.grep_event_paths_from_physiological_file_id(
                physiological_file_id
            )

            if not event_paths:
                event_paths = []

                event_data = utilities.read_tsv_file(event_data_file.path)
                # copy the event file to the LORIS BIDS import directory
                event_path = self.copy_file_to_loris_bids_dir(
                    event_data_file.path, derivatives
                )
                # get the blake2b hash of the task events file
                blake2 = blake2b(event_data_file.path.encode('utf-8')).hexdigest()
                # insert event data in the database
                physiological.insert_event_file(
                    event_data, event_path, physiological_file_id, blake2
                )

                event_paths.extend([event_path])

                # get events.json file and insert
                # subject-specific metadata
                event_metadata_file = self.bids_layout.get_nearest(
                    event_data_file.path,
                    return_type = 'tuple',
                    strict = False,
                    extension = 'json',
                    suffix = 'events',
                    all_ = False,
                    full_search = False,
                    subject=self.psc_id,
                )
                inheritance = False

                if not event_metadata_file:
                    # global events metadata
                    event_metadata_file = self.bids_layout.get_nearest(
                        event_data_file.path,
                        return_type = 'tuple',
                        strict = False,
                        extension = 'json',
                        suffix = 'events',
                        all_ = False,
                        full_search = False,
                    )
                    inheritance = True

                    if not event_metadata_file:
                        message = '\nWARNING: no events metadata files (event.json) associated' \
                                  'with physiological file ID ' + physiological_file_id
                        print(message)
                    else:
                        # copy the event file to the LORIS BIDS import directory
                        event_metadata_path = self.copy_file_to_loris_bids_dir(
                            event_metadata_file.path, derivatives, inheritance
                        )
                        # load json data
                        with open(event_metadata_file.path) as metadata_file:
                            event_metadata = json.load(metadata_file)
                        # get the blake2b hash of the json events file
                        blake2 = blake2b(event_metadata_file.path.encode('utf-8')).hexdigest()
                        # insert event metadata in the database
                        physiological.insert_event_metadata(
                            event_metadata, event_metadata_path, physiological_file_id, blake2
                        )

                        event_paths.extend([event_metadata_path])

                        # insert assembled HED annotations
                        physiological.insert_event_assembled_hed_tags(
                            self.data_dir, event_path, event_metadata_path, physiological_file_id
                        )

        return event_paths

    def fetch_and_insert_annotation_files(
            self, physiological_file_id, original_physiological_file_path, derivatives=False):
        """
        Gather raw channel file information to insert into
        the physiological_annotation_* tables. Once all the information has been gathered,
        it will call Physiological.insert_annotation_file that will perform the
        insertion into the physiological_annotation_* tables, linking them to the
        PhysiologicalFileID already registered.

        :param physiological_file_id: PhysiologicalFileID of the associated
                                      physiological file already inserted into
                                      the physiological_file table
         :type physiological_file_id: int
        :param original_physiological_file_path: path of the original physiological file
         :type original_file_data:               string
        :param derivatives:                      True if the event file to insert is a derivative file.
                                                 Set by default to False when inserting raw file.
         :type derivatives:                      boolean

        :return: channel file path in the /DATA_DIR/bids_import directory
         :rtype: str
        """

        # load the Physiological object that will be used to insert the
        # physiological data into the database
        physiological = Physiological(self.db, self.verbose)

        annotation_data_files = self.bids_layout.get_nearest(
            original_physiological_file_path,
            return_type = 'tuple',
            strict = False,
            extension = 'tsv',
            suffix = 'annotations',
            all_ = True,
            full_search = False,
            subject=self.psc_id,
        )

        if not(annotation_data_files):
            message = "WARNING: no annotations files associated with " \
                      "physiological file ID " + str(physiological_file_id)
            print(message)
            return None
        else:
            physiological_annotation_file_obj = PhysiologicalAnnotationFile(self.db, self.verbose)
            annotation_paths = physiological_annotation_file_obj.grep_annotation_paths_from_physiological_file_id(
                physiological_file_id
            )

            if not annotation_paths:
                annotation_paths = []

                for annotation_data_file in annotation_data_files:
                    # copy the annotation file to the LORIS BIDS import directory

                    annotation_metadata_file = self.bids_layout.get_nearest(
                        annotation_data_file.path,
                        return_type = 'tuple',
                        strict = False,
                        extension = 'json',
                        suffix = 'annotations',
                        all_ = False,
                        full_search = False,
                        subject=self.psc_id,
                    )

                    annotation_data_path = self.copy_file_to_loris_bids_dir(
                        annotation_data_file.path, derivatives
                    )

                    annotation_metadata_path = self.copy_file_to_loris_bids_dir(
                        annotation_metadata_file.path, derivatives
                    )

                    # get the blake2b hash of the metadata file
                    blake2 = blake2b(annotation_metadata_file.path.encode('utf-8')).hexdigest()
                    # insert annotation metadata in the database
                    with open(annotation_metadata_file.path) as metadata_file:
                        annotation_metadata = json.load(metadata_file)

                    annotation_metadata_id = physiological.insert_annotation_metadata(
                        annotation_metadata, annotation_metadata_path, physiological_file_id, blake2
                    )

                    # get the blake2b hash of the data file
                    blake2 = blake2b(annotation_data_file.path.encode('utf-8')).hexdigest()
                    # insert annotation data in the database
                    annotation_data = utilities.read_tsv_file(annotation_data_file.path)
                    annotation_data_id = physiological.insert_annotation_data(
                        annotation_data, annotation_data_path, physiological_file_id, blake2
                    )

                    physiological_annotation_rel_obj = PhysiologicalAnnotationRel(self.db, self.verbose)
                    physiological_annotation_rel_obj.insert(annotation_data_id, annotation_metadata_id)

                    annotation_paths.extend([annotation_data_path, annotation_metadata_path])

        return annotation_paths

    def copy_file_to_loris_bids_dir(self, file, derivatives=False, inheritance=False):
        """
        Wrapper around the utilities.copy_file function that copies the file
        to the LORIS BIDS import directory and returns the relative path of the
        file (without the data_dir part).

        :param file: full path to the original file
         :type file: str
        :param derivatives: True if the file to copy is a derivative file.
                            Set by default to False when inserting raw file.
         :type derivatives: boolean

        :return: relative path to the copied file
         :rtype: str
        """

        # Handle derivatives differently
        # Data path structure is unpredictable, so keep the same relative path
        if derivatives:
            copy_file = str.replace(
                file,
                self.bids_layout.root,
                ""
            )
            copy_file = self.loris_bids_root_dir + copy_file

            # create derivative directories
            lib.utilities.create_dir(
                os.path.dirname(copy_file),
                self.verbose
            )
        else :
            # determine the path of the copied file
            copy_file = ""
            if not inheritance:
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
            copy_file = self.loris_bids_root_dir + copy_file

        # copy the file
        utilities.copy_file(file, copy_file, self.verbose)

        # determine the relative path and return it
        relative_path = copy_file.replace(self.data_dir, "")

        return relative_path

    def create_and_insert_archive(self, files_to_archive, archive_rel_name,
                                  eeg_file_id):
        """
        Create an archive with all electrophysiology files associated to a
        specific recording (including electrodes.tsv, channels.tsv etc...)

        :param files_to_archive: tuple with the list of files to include in
                                 the archive
         :type files_to_archive: tuple
        :param archive_rel_name: path to the archive relative to data_dir
         :type archive_rel_name: str
        :param eeg_file_id     : PhysiologicalFileID
         :type eeg_file_id     : int
        """

        # load the Physiological object that will be used to insert the
        # physiological archive into the database
        physiological = Physiological(self.db, self.verbose)

        # check if archive is on the filesystem
        archive_full_path = os.path.join(self.data_dir, archive_rel_name)
        blake2            = None
        if os.path.isfile(archive_full_path):
            blake2 = blake2b(archive_full_path.encode('utf-8')).hexdigest()

        # check if archive already inserted in database and matches the one
        # on the filesystem using blake2b hash
        result = physiological.grep_archive_info_from_file_id(eeg_file_id)
        if result:
            if not blake2:
                message = '\nERROR: no archive was found on the filesystem ' + \
                          'while an entry was found in the database for '   + \
                          'PhysiologicalFileID = ' + str(eeg_file_id)
                print(message)
                exit(lib.exitcode.MISSING_FILES)
            elif result['Blake2bHash'] != blake2:
                message = '\nERROR: blake2b hash of ' + archive_full_path     +\
                          ' does not match the one stored in the database.'   +\
                          '\nblake2b of ' + archive_full_path + ': ' + blake2 +\
                          '\nblake2b in the database: ' + result['blake2b_hash']
                print(message)
                exit(lib.exitcode.CORRUPTED_FILE)
            else:
                return

        # create the archive file
        utilities.create_archive(files_to_archive, archive_rel_name, self.data_dir)

        # insert the archive file in physiological_archive
        blake2 = blake2b(archive_full_path.encode('utf-8')).hexdigest()
        archive_info = {
            'PhysiologicalFileID': eeg_file_id,
            'Blake2bHash'        : blake2,
            'FilePath'           : archive_rel_name
        }
        physiological.insert_archive_file(archive_info)

    def create_and_insert_annotation_archive(self, files_to_archive, archive_rel_name, eeg_file_id):
        """
        Create an archive with all annotations files associated to a specific recording

        :param files_to_archive: tuple with the list of files to include in
                                 the archive
         :type files_to_archive: tuple
        :param archive_rel_name: path to the archive relative to data_dir
         :type archive_rel_name: str
        :param eeg_file_id     : PhysiologicalFileID
         :type eeg_file_id     : int
        """

        # check if archive is on the filesystem
        archive_full_path = os.path.join(self.data_dir, archive_rel_name)
        blake2            = None
        if os.path.isfile(archive_full_path):
            blake2 = blake2b(archive_full_path.encode('utf-8')).hexdigest()

        # check if archive already inserted in database and matches the one
        # on the filesystem using blake2b hash
        physiological_annotation_archive_obj = PhysiologicalAnnotationArchive(self.db, self.verbose)
        results = physiological_annotation_archive_obj.grep_from_physiological_file_id(eeg_file_id)

        if results:
            result = results[0]
            if not blake2:
                message = '\nERROR: no archive was found on the filesystem ' + \
                          'while an entry was found in the database for '   + \
                          'PhysiologicalFileID = ' + str(eeg_file_id)
                print(message)
                exit(lib.exitcode.MISSING_FILES)
            elif result['Blake2bHash'] != blake2:
                message = '\nERROR: blake2b hash of ' + archive_full_path     +\
                          ' does not match the one stored in the database.'   +\
                          '\nblake2b of ' + archive_full_path + ': ' + blake2 +\
                          '\nblake2b in the database: ' + result['blake2b_hash']
                print(message)
                exit(lib.exitcode.CORRUPTED_FILE)
            else:
                return

        # create the archive file
        utilities.create_archive(files_to_archive, archive_rel_name, self.data_dir)

        # insert the archive into the physiological_annotation_archive table
        blake2 = blake2b(archive_full_path.encode('utf-8')).hexdigest()
        physiological_annotation_archive_obj.insert(eeg_file_id, blake2, archive_rel_name)

    def create_and_insert_event_archive(self, files_to_archive, archive_rel_name, eeg_file_id):
        """
        Create an archive with all event files associated to a specific recording

        :param files_to_archive: tuple with the list of files to include in
                                 the archive
         :type files_to_archive: tuple
        :param archive_rel_name: path to the archive relative to data_dir
         :type archive_rel_name: str
        :param eeg_file_id     : PhysiologicalFileID
         :type eeg_file_id     : int
        """

        # check if archive is on the filesystem
        archive_full_path = os.path.join(self.data_dir, archive_rel_name)
        blake2            = None
        if os.path.isfile(archive_full_path):
            blake2 = blake2b(archive_full_path.encode('utf-8')).hexdigest()

        # check if archive already inserted in database and matches the one
        # on the filesystem using blake2b hash
        physiological_event_archive_obj = PhysiologicalEventArchive(self.db, self.verbose)
        results = physiological_event_archive_obj.grep_from_physiological_file_id(eeg_file_id)

        if results:
            result = results[0]
            if not blake2:
                message = '\nERROR: no archive was found on the filesystem ' + \
                          'while an entry was found in the database for '   + \
                          'PhysiologicalFileID = ' + str(eeg_file_id)
                print(message)
                exit(lib.exitcode.MISSING_FILES)
            elif result['Blake2bHash'] != blake2:
                message = '\nERROR: blake2b hash of ' + archive_full_path     +\
                          ' does not match the one stored in the database.'   +\
                          '\nblake2b of ' + archive_full_path + ': ' + blake2 +\
                          '\nblake2b in the database: ' + result['blake2b_hash']
                print(message)
                exit(lib.exitcode.CORRUPTED_FILE)
            else:
                return

        # create the archive file
        utilities.create_archive(files_to_archive, archive_rel_name, self.data_dir)

        # insert the archive into the physiological_annotation_archive table
        blake2 = blake2b(archive_full_path.encode('utf-8')).hexdigest()
        physiological_event_archive_obj.insert(eeg_file_id, blake2, archive_rel_name)

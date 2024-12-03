"""Deals with EEG BIDS datasets and register them into the database."""

import getpass
import json
import os
from typing import Any, Literal

import lib.exitcode
import lib.utilities as utilities
from lib.database import Database
from lib.database_lib.config import Config
from lib.database_lib.physiological_event_archive import PhysiologicalEventArchive
from lib.database_lib.physiological_event_file import PhysiologicalEventFile
from lib.database_lib.physiological_modality import PhysiologicalModality
from lib.database_lib.physiological_output_type import PhysiologicalOutputType
from lib.db.models.session import DbSession
from lib.imaging_lib.bids.dataset import BidsDataType
from lib.physiological import Physiological
from lib.util.crypto import compute_file_blake2b_hash


class Eeg:
    """
    This class reads the BIDS EEG data structure and register the EEG datasets
    into the database by calling the lib.physiological class.
    """

    def __init__(
        self, data_type: BidsDataType, session: DbSession, db: Database, verbose: bool, data_dir: str,
        loris_bids_eeg_rel_dir: str, loris_bids_root_dir: str | None, dataset_tag_dict: dict[Any, Any],
        dataset_type: Literal['raw', 'derivative'] | None,
    ):
        """
        Constructor method for the Eeg class.

        :param data_type    : The BIDS data type object.
        :param session      : The session database object.
        :param db           : Database class object
        :param verbose      : whether to be verbose
        :param data_dir     : LORIS data directory path (usually /data/PROJECT/data)
        :param loris_bids_eeg_rel_dir: LORIS BIDS EEG relative dir path to data_dir
        :param loris_bids_root_dir   : LORIS BIDS root directory path
        :param dataset_tag_dict      : Dict of dataset-inherited HED tags
        :param dataset_type          : raw | derivative. Type of the dataset
        """

        # config
        self.config_db_obj = Config(db, verbose)

        # load bids objects
        self.data_type   = data_type
        self.bids_layout = data_type.root_dataset.layout

        # load the LORIS BIDS import root directory where the eeg files will
        # be copied
        self.loris_bids_eeg_rel_dir = loris_bids_eeg_rel_dir
        self.loris_bids_root_dir    = loris_bids_root_dir
        self.data_dir               = data_dir

        # load dataset tag dict. Used to ensure HED tags aren't duplicated
        self.dataset_tag_dict   = dataset_tag_dict

        # load database handler object and verbose bool
        self.db      = db
        self.verbose = verbose

        # find corresponding CandID and SessionID in LORIS
        self.session = session

        hed_query = 'SELECT * FROM hed_schema_nodes WHERE 1'
        self.hed_union = self.db.pselect(query=hed_query, args=())

        # check if a tsv with acquisition dates or age is available for the subject
        self.scans_file = None
        if self.bids_layout.get(suffix='scans', subject=self.data_type.subject.label, return_type='filename'):
            self.scans_file = self.bids_layout.get(
                suffix='scans',
                subject=self.data_type.subject.label,
                return_type='filename'
            )[0]

        # register the data into LORIS
        if (dataset_type and dataset_type == 'raw'):
            self.register_data(detect=False)
        elif (dataset_type and dataset_type == 'derivative'):
            self.register_data(derivatives=True, detect=False)
        else:
            self.register_data()
            self.register_data(derivatives=True)

    def grep_bids_files(self, bids_type):
        """
        Greps the BIDS files and their layout information from the BIDSLayout
        and return that list.

        :param bids_type: the BIDS type to use to grep files (events,
                          channels, eeg, electrodes)
         :type bids_type: str

        :return: list of files from the BIDS layout
         :rtype: list
        """

        if self.data_type.session.label:
            return self.bids_layout.get(
                subject     = self.data_type.subject.label,
                session     = self.data_type.session.label,
                datatype    = self.data_type.name,
                suffix      = bids_type,
                return_type = 'filename'
            )
        else:
            return self.bids_layout.get(
                subject     = self.data_type.subject.label,
                datatype    = self.data_type.name,
                suffix      = bids_type,
                return_type = 'filename'
            )

    def register_data(self, derivatives=False, detect=True):
        """
        Registers raw and derivatives EEG data and related files into the following tables:
            - physiological_file
            - physiological_parameter_file
            - physiological_electrode
            - physiological_coord_system
            - physiological_channel
            - physiological_task_event
            - physiological_event_*

        :param derivatives: True if the EEG file to insert is a derivative file.
                            Set by default to False when inserting raw file.
         :type derivatives: boolean
        :param detect:      True if we want to perform a automatic detections of the derivatives files
                            in case of mixed dataset.
                            Set by default to True.
         :type detect:      boolean
        """

        # insert EEG file
        inserted_eegs = self.fetch_and_insert_eeg_files(derivatives, detect)

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

            # archive all files in a tar ball for downloading all files at once
            files_to_archive = (os.path.join(self.data_dir, eeg_file_path),)

            if eegjson_file_path:
                files_to_archive = (*files_to_archive, os.path.join(self.data_dir, eegjson_file_path))
            if fdt_file_path:
                files_to_archive = (*files_to_archive, os.path.join(self.data_dir, fdt_file_path))
            if electrode_file_path:
                files_to_archive = (*files_to_archive, os.path.join(self.data_dir, electrode_file_path))
            if event_file_paths:
                # archive all event files in a tar ball for event download
                event_files_to_archive = ()

                for event_file_path in event_file_paths:
                    files_to_archive = (*files_to_archive, os.path.join(self.data_dir, event_file_path))
                    event_files_to_archive = (*event_files_to_archive, os.path.join(self.data_dir, event_file_path))

                event_archive_rel_name = os.path.splitext(event_file_paths[0])[0] + ".tgz"
                self.create_and_insert_event_archive(
                    event_files_to_archive, event_archive_rel_name, eeg_file_id
                )

            if channel_file_path:
                files_to_archive = (*files_to_archive, os.path.join(self.data_dir, channel_file_path))

            archive_rel_name = os.path.splitext(eeg_file_path)[0] + ".tgz"
            self.create_and_insert_archive(
                files_to_archive, archive_rel_name, eeg_file_id
            )

            # create data chunks for React visualization
            eeg_viz_enabled = self.config_db_obj.get_config("useEEGBrowserVisualizationComponents")
            if eeg_viz_enabled == 'true' or eeg_viz_enabled == '1':
                physiological.create_chunks_for_visualization(eeg_file_id, self.data_dir)

    def fetch_and_insert_eeg_files(self, derivatives=False, detect=True):
        """
        Gather EEG file information to insert into physiological_file and
        physiological_parameter_file. Once all the information has been
        gathered, it will call self.insert_physiological_file that will
        perform the insertion into physiological_file and
        physiological_parameter_file.

        :param derivatives: True if the EEG file to insert is a derivative file.
                            Set by default to False when inserting raw file.
         :type derivatives: boolean
        :param detect:      True if we want to perform a automatic detections of the derivatives files
                            in case of mixed dataset.
                            Set by default to True.
         :type detect:      boolean
        :return: dictionary with registered file ID and path to its file
         :rtype: dict
        """

        inserted_eegs = []
        # load the Physiological object that will be used to insert the
        # physiological data into the database
        physiological = Physiological(self.db, self.verbose)

        if detect:
            # TODO if derivatives, grep the source file as well as the input file ID???
            eeg_files = self.bids_layout.get(
                subject   = self.data_type.subject.label,
                session   = self.data_type.session.label,
                scope     = 'derivatives' if derivatives else 'raw',
                suffix    = self.data_type.name,
                extension = ['set', 'edf', 'vhdr', 'vmrk', 'eeg', 'bdf']
            )
        else:
            eeg_files = self.bids_layout.get(
                subject   = self.data_type.subject.label,
                session   = self.data_type.session.label,
                suffix    = self.data_type.name,
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
                suffix = self.data_type.name,
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

                eegjson_file_path = eegjson_file.path.replace(self.data_dir, '')
                if self.loris_bids_root_dir:
                    # copy the JSON file to the LORIS BIDS import directory
                    eegjson_file_path = self.copy_file_to_loris_bids_dir(
                        eegjson_file.path, derivatives
                    )

                eeg_file_data['eegjson_file'] = eegjson_file_path
                json_blake2 = compute_file_blake2b_hash(eegjson_file.path)
                eeg_file_data['physiological_json_file_blake2b_hash'] = json_blake2

            # greps the file type from the ImagingFileTypes table
            file_type = physiological.determine_file_type(eeg_file.path)

            # grep the output type from the physiological_output_type table
            output_type = 'derivative' if derivatives else 'raw'
            output_type_obj = PhysiologicalOutputType(self.db, self.verbose)
            output_type_id = output_type_obj.grep_id_from_output_type(output_type)

            # get the acquisition date of the EEG file or the age at the time of the EEG recording
            eeg_acq_time = None
            if self.scans_file:
                tsv_scan = self.data_type.session.get_tsv_scan(os.path.basename(self.scans_file))

                eeg_acq_time = tsv_scan.acquisition_time
                eeg_file_data['age_at_scan'] = tsv_scan.age_at_scan

                if self.loris_bids_root_dir:
                    # copy the scans.tsv file to the LORIS BIDS import directory
                    scans_path = self.copy_scans_tsv_file_to_loris_bids_dir()

                eeg_file_data['scans_tsv_file'] = scans_path
                scans_blake2 = compute_file_blake2b_hash(self.scans_file)
                eeg_file_data['physiological_scans_tsv_file_bake2hash'] = scans_blake2

            # if file type is set and fdt file exists, append fdt path to the
            # eeg_file_data dictionary
            fdt_file_path = None
            if file_type == 'set' and fdt_file:
                fdt_file_path = fdt_file.path.replace(self.data_dir, '')
                if self.loris_bids_root_dir:
                    # copy the fdt file to the LORIS BIDS import directory
                    fdt_file_path = self.copy_file_to_loris_bids_dir(
                        fdt_file.path, derivatives
                    )

                eeg_file_data['fdt_file'] = fdt_file_path
                fdt_blake2 = compute_file_blake2b_hash(fdt_file.path)
                eeg_file_data['physiological_fdt_file_blake2b_hash'] = fdt_blake2

            # append the blake2b to the eeg_file_data dictionary
            blake2 = compute_file_blake2b_hash(eeg_file.path)
            eeg_file_data['physiological_file_blake2b_hash'] = blake2

            # check that the file using blake2b is not already inserted before
            # inserting it
            result         = physiological.grep_file_id_from_hash(blake2)
            physio_file_id = result['PhysiologicalFileID'] if result else None
            eeg_path       = result['FilePath']            if result else None

            physiological_modality = PhysiologicalModality(self.db, self.verbose)

            if not physio_file_id:
                # grep the modality ID from physiological_modality table
                modality_id = physiological_modality.grep_id_from_modality_value(self.data_type.name)

                eeg_path = eeg_file.path.replace(self.data_dir, '')
                if self.loris_bids_root_dir:
                    # copy the eeg_file to the LORIS BIDS import directory
                    eeg_path = self.copy_file_to_loris_bids_dir(
                        eeg_file.path, derivatives
                    )

                # insert the file along with its information into
                # physiological_file and physiological_parameter_file tables
                eeg_file_info = {
                    'FileType': file_type,
                    'FilePath': eeg_path,
                    'SessionID': self.session.id,
                    'AcquisitionTime': eeg_acq_time,
                    'InsertedByUser': getpass.getuser(),
                    'PhysiologicalOutputTypeID': output_type_id,
                    'PhysiologicalModalityID': modality_id
                }
                physio_file_id = physiological.insert_physiological_file(
                    eeg_file_info, eeg_file_data
                )

                if self.loris_bids_root_dir:
                    # If we copy the file in assembly_bids and
                    # if the EEG file was a set file, then update the filename for the .set
                    # and .fdt files in the .set file so it can find the proper file for
                    # visualization and analyses
                    if file_type == 'set':
                        set_full_path = os.path.join(self.data_dir, eeg_path)
                        width_fdt_file = True if 'fdt_file' in eeg_file_data.keys() else False

                        file_paths_updated = utilities.update_set_file_path_info(set_full_path, width_fdt_file)
                        if not file_paths_updated:
                            message = "WARNING: cannot update the set file " + eeg_path + " path info"
                            print(message)

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

        electrode_files = self.bids_layout.get_nearest(
            original_physiological_file_path,
            return_type = 'tuple',
            strict = False,
            extension = 'tsv',
            suffix = 'electrodes',
            all_ = True,  # get all existing electrode files
            full_search = False,
        )

        if not electrode_files:
            message = "WARNING: no electrode file associated with " \
                      "physiological file ID " + str(physiological_file_id)
            print(message)
            return None
        else:
            # maybe several electrode files
            for electrode_file in electrode_files:
                result = physiological.grep_electrode_from_physiological_file_id(
                    physiological_file_id
                )
                if not result:
                    electrode_data = utilities.read_tsv_file(electrode_file.path)
                    electrode_path = electrode_file.path.replace(self.data_dir, '')
                    if self.loris_bids_root_dir:
                        # copy the electrode file to the LORIS BIDS import directory
                        electrode_path = self.copy_file_to_loris_bids_dir(
                            electrode_file.path, derivatives
                        )
                    # get the blake2b hash of the electrode file
                    blake2 = compute_file_blake2b_hash(electrode_file.path)

                    # insert the electrode data in the database
                    electrode_ids = physiological.insert_electrode_file(
                        electrode_data, electrode_path, physiological_file_id, blake2
                    )

                    # get coordsystem.json file
                    # subject-specific metadata
                    coordsystem_metadata_file = self.bids_layout.get_nearest(
                        electrode_file.path,
                        return_type = 'tuple',
                        strict = False,
                        extension = 'json',
                        suffix = 'coordsystem',
                        all_ = False,
                        full_search = False,
                        subject=self.data_type.subject.label,
                    )
                    if not coordsystem_metadata_file:
                        message = '\nWARNING: no electrode metadata files (coordsystem.json) ' \
                                  f'associated with physiological file ID {physiological_file_id}'
                        print(message)

                        # insert default (not registered) coordsystem in the database
                        physiological.insert_electrode_metadata(
                            None,
                            None,
                            physiological_file_id,
                            None,
                            electrode_ids
                        )
                    else:
                        electrode_metadata_path = coordsystem_metadata_file.path.replace(self.data_dir, '')
                        if self.loris_bids_root_dir:
                            # copy the electrode metadata file to the LORIS BIDS import directory
                            electrode_metadata_path = self.copy_file_to_loris_bids_dir(
                                coordsystem_metadata_file.path, derivatives
                            )
                        # load json data
                        with open(coordsystem_metadata_file.path) as metadata_file:
                            electrode_metadata = json.load(metadata_file)
                        # get the blake2b hash of the json events file
                        blake2 = compute_file_blake2b_hash(coordsystem_metadata_file.path)
                        # insert event metadata in the database
                        physiological.insert_electrode_metadata(
                            electrode_metadata,
                            electrode_metadata_path,
                            physiological_file_id,
                            blake2,
                            electrode_ids
                        )

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
                channel_path = channel_file.path.replace(self.data_dir, '')
                if self.loris_bids_root_dir:
                    # copy the channel file to the LORIS BIDS import directory
                    channel_path = self.copy_file_to_loris_bids_dir(
                        channel_file.path, derivatives
                    )
                # get the blake2b hash of the channel file
                blake2 = compute_file_blake2b_hash(channel_file.path)
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

            file_tag_dict = {}
            if not event_paths:
                event_paths = []
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
                    subject=self.data_type.subject.label,
                )
                inheritance = False

                if not event_metadata_file:
                    message = '\nWARNING: no events metadata files (events.json) associated ' \
                              'with physiological file ID ' + str(physiological_file_id)
                    print(message)
                else:
                    event_metadata_path = event_metadata_file.path.replace(self.data_dir, '')
                    if self.loris_bids_root_dir:
                        # copy the event file to the LORIS BIDS import directory
                        event_metadata_path = self.copy_file_to_loris_bids_dir(
                            event_metadata_file.path, derivatives, inheritance
                        )
                    # load json data
                    with open(event_metadata_file.path) as metadata_file:
                        event_metadata = json.load(metadata_file)
                    # get the blake2b hash of the json events file
                    blake2 = compute_file_blake2b_hash(event_metadata_file.path)
                    # insert event metadata in the database
                    _, file_tag_dict = physiological.insert_event_metadata(
                        event_metadata=event_metadata,
                        event_metadata_file=event_metadata_path,
                        physiological_file_id=physiological_file_id,
                        project_id=self.session.project_id,
                        blake2=blake2,
                        project_wide=False,
                        hed_union=self.hed_union
                    )
                    event_paths.extend([event_metadata_path])

            # get events.tsv file and insert
            event_data = utilities.read_tsv_file(event_data_file.path)
            event_path = event_data_file.path.replace(self.data_dir, '')
            if self.loris_bids_root_dir:
                # copy the event file to the LORIS BIDS import directory
                event_path = self.copy_file_to_loris_bids_dir(
                    event_data_file.path, derivatives
                )
            # get the blake2b hash of the task events file
            blake2 = compute_file_blake2b_hash(event_data_file.path)

            # insert event data in the database
            physiological.insert_event_file(
                event_data=event_data,
                event_file=event_path,
                physiological_file_id=physiological_file_id,
                project_id=self.session.project_id,
                blake2=blake2,
                dataset_tag_dict=self.dataset_tag_dict,
                file_tag_dict=file_tag_dict,
                hed_union=self.hed_union
            )

            event_paths.extend([event_path])

        return event_paths

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
            if self.data_type.session.label:
                copy_file += os.path.basename(file)
            else:
                # make sure the ses- is included in the new filename if using
                # default visit label from the LORIS config
                copy_file += str.replace(
                    os.path.basename(file),
                    "sub-" + self.data_type.subject.label,
                    "sub-" + self.data_type.subject.label + "_ses-" + self.default_vl
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
        (archive_rel_name, archive_full_path) = self.get_archive_paths(archive_rel_name)
        if os.path.isfile(archive_full_path):
            blake2 = compute_file_blake2b_hash(archive_full_path)
        else:
            blake2 = None

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
        utilities.create_archive(files_to_archive, archive_full_path)

        # insert the archive file in physiological_archive
        blake2 = compute_file_blake2b_hash(archive_full_path)
        archive_info = {
            'PhysiologicalFileID': eeg_file_id,
            'Blake2bHash'        : blake2,
            'FilePath'           : archive_rel_name
        }
        physiological.insert_archive_file(archive_info)

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
        (archive_rel_name, archive_full_path) = self.get_archive_paths(archive_rel_name)
        if os.path.isfile(archive_full_path):
            blake2 = compute_file_blake2b_hash(archive_full_path)
        else:
            blake2 = None

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
        utilities.create_archive(files_to_archive, archive_full_path)

        # insert the archive into the physiological_annotation_archive table
        blake2 = compute_file_blake2b_hash(archive_full_path)
        physiological_event_archive_obj.insert(eeg_file_id, blake2, archive_rel_name)

    def get_archive_paths(self, archive_rel_name):
        package_path = self.config_db_obj.get_config("prePackagedDownloadPath")
        if package_path:
            raw_package_dir = os.path.join(package_path, 'raw')
            os.makedirs(raw_package_dir, exist_ok=True)
            archive_rel_name = os.path.basename(archive_rel_name)
            archive_full_path = os.path.join(raw_package_dir, archive_rel_name)
        else:
            archive_full_path = os.path.join(self.data_dir, archive_rel_name)

        return (archive_rel_name, archive_full_path)

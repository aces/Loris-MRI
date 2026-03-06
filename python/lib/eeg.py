"""Deals with EEG BIDS datasets and register them into the database."""

import json
import os
import sys
from pathlib import Path

from loris_bids_reader.eeg.channels import BidsEegChannelsTsvFile
from loris_bids_reader.eeg.sidecar import BidsEegSidecarJsonFile
from loris_bids_reader.files.events import BidsEventsTsvFile
from loris_bids_reader.files.scans import BidsScansTsvFile
from loris_bids_reader.info import BidsDataTypeInfo
from loris_utils.crypto import compute_file_blake2b_hash

import lib.exitcode
import lib.utilities as utilities
from lib.config import get_eeg_pre_package_download_dir_path_config, get_eeg_viz_enabled_config
from lib.database_lib.physiological_event_archive import PhysiologicalEventArchive
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.session import DbSession
from lib.db.queries.physio_file import try_get_physio_file_with_path
from lib.env import Env
from lib.import_bids_dataset.copy_files import copy_scans_tsv_file_to_loris_bids_dir
from lib.import_bids_dataset.file_type import get_check_bids_imaging_file_type_from_extension
from lib.import_bids_dataset.physio import (
    get_check_bids_physio_file_hash,
    get_check_bids_physio_modality,
    get_check_bids_physio_output_type,
)
from lib.logging import log
from lib.physio.chunking import create_physio_channels_chunks
from lib.physio.file import insert_physio_file
from lib.physio.parameters import insert_physio_file_parameters
from lib.physiological import Physiological


class Eeg:
    """
    This class reads the BIDS EEG data structure and register the EEG datasets
    into the database by calling the lib.physiological class.
    """

    def __init__(self, env: Env, bids_layout, bids_info: BidsDataTypeInfo, session: DbSession, db,
                 data_dir, loris_bids_eeg_rel_dir,
                 loris_bids_root_dir, dataset_tag_dict, dataset_type):
        """
        Constructor method for the Eeg class.

        :param bids_reader  : dictionary with BIDS reader information
         :type bids_reader  : dict
        :param bids_info    : the BIDS data type information
        :param session      : The LORIS session the EEG datasets are linked to
        :param db           : Database class object
         :type db           : object
        :param data_dir     : LORIS data directory path (usually /data/PROJECT/data)
         :type data_dir     : str
        :param loris_bids_eeg_rel_dir: LORIS BIDS EEG relative dir path to data_dir
         :type loris_bids_eeg_rel_dir: str
        :param loris_bids_root_dir   : LORIS BIDS root directory path
         :type loris_bids_root_dir   : str
        :param dataset_tag_dict      : Dict of dataset-inherited HED tags
         :type dataset_tag_dict      : dict
        :param dataset_type          : raw | derivative. Type of the dataset
         :type dataset_type          : string
        """

        self.env = env

        # load bids objects
        self.bids_layout = bids_layout

        # load the LORIS BIDS import root directory where the eeg files will
        # be copied
        self.loris_bids_eeg_rel_dir = loris_bids_eeg_rel_dir
        self.loris_bids_root_dir    = loris_bids_root_dir
        self.data_dir               = data_dir

        # load bids subject, visit and modality
        self.bids_info = bids_info

        # load dataset tag dict. Used to ensure HED tags aren't duplicated
        self.dataset_tag_dict   = dataset_tag_dict

        # load database handler object
        self.db = db

        # find corresponding CandID and SessionID in LORIS
        self.session = session

        hed_query = 'SELECT * FROM hed_schema_nodes WHERE 1'
        self.hed_union = self.db.pselect(query=hed_query, args=())

        # check if a tsv with acquisition dates or age is available for the subject
        self.scans_file = None
        if self.bids_layout.get(suffix='scans', subject=self.bids_info.subject, return_type='filename'):
            scans_file_path = self.bids_layout.get(
                suffix='scans',
                subject=self.bids_info.subject,
                return_type='filename',
            )[0]
            self.scans_file = BidsScansTsvFile(Path(scans_file_path))

        # register the data into LORIS
        if (dataset_type and dataset_type == 'raw'):
            self.register_data(detect=False)
        elif (dataset_type and dataset_type == 'derivative'):
            self.register_data(derivatives=True, detect=False)
        else:
            self.register_data()
            self.register_data(derivatives=True)

        env.db.commit()

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

        if self.bids_info.session is not None:
            return self.bids_layout.get(
                subject     = self.bids_info.subject,
                session     = self.bids_info.session,
                datatype    = self.bids_info.data_type,
                suffix      = bids_type,
                return_type = 'filename'
            )
        else:
            return self.bids_layout.get(
                subject     = self.bids_info.subject,
                datatype    = self.bids_info.data_type,
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

        for inserted_eeg in inserted_eegs:
            eeg_file: DbPhysioFile = inserted_eeg['file']
            eegjson_file_path      = inserted_eeg['eegjson_file_path']
            fdt_file_path          = inserted_eeg['fdt_file_path']
            original_file_data     = inserted_eeg['original_file_data']

            # insert related electrode, channel and event information
            electrode_file_path = self.fetch_and_insert_electrode_file(
                eeg_file,
                original_file_data.path,
                derivatives
            )

            channel_file_path = self.fetch_and_insert_channel_file(
                eeg_file,
                original_file_data.path,
                derivatives
            )

            event_file_paths = self.fetch_and_insert_event_files(
                eeg_file,
                original_file_data.path,
                derivatives
            )

            # archive all files in a tar ball for downloading all files at once
            files_to_archive: list[str] = [os.path.join(self.data_dir, eeg_file.path)]

            if eegjson_file_path:
                files_to_archive.append(os.path.join(self.data_dir, eegjson_file_path))
            if fdt_file_path:
                files_to_archive.append(os.path.join(self.data_dir, fdt_file_path))
            if electrode_file_path:
                files_to_archive.append(os.path.join(self.data_dir, electrode_file_path))
            if event_file_paths:
                # archive all event files in a tar ball for event download
                event_files_to_archive: list[str] = []

                for event_file_path in event_file_paths:
                    files_to_archive.append(os.path.join(self.data_dir, event_file_path))
                    event_files_to_archive.append(os.path.join(self.data_dir, event_file_path))

                event_archive_rel_name = os.path.splitext(event_file_paths[0])[0] + ".tgz"
                self.create_and_insert_event_archive(
                    event_files_to_archive, event_archive_rel_name, eeg_file
                )

            if channel_file_path:
                files_to_archive.append(os.path.join(self.data_dir, channel_file_path))

            archive_rel_name = os.path.splitext(eeg_file.path)[0] + ".tgz"
            self.create_and_insert_archive(
                files_to_archive, archive_rel_name, eeg_file
            )

            # create data chunks for React visualization
            eeg_viz_enabled = get_eeg_viz_enabled_config(self.env)
            if eeg_viz_enabled:
                create_physio_channels_chunks(self.env, eeg_file, Path(original_file_data.path))

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

        if detect:
            # TODO if derivatives, grep the source file as well as the input file ID???
            eeg_files = self.bids_layout.get(
                subject   = self.bids_info.subject,
                session   = self.bids_info.session,
                scope     = 'derivatives' if derivatives else 'raw',
                suffix    = self.bids_info.data_type,
                extension = ['set', 'edf', 'vhdr', 'vmrk', 'eeg', 'bdf']
            )
        else:
            eeg_files = self.bids_layout.get(
                subject   = self.bids_info.subject,
                session   = self.bids_info.session,
                suffix    = self.bids_info.data_type,
                extension = ['set', 'edf', 'vhdr', 'vmrk', 'eeg', 'bdf']
            )

        # return if no eeg_file was found
        if not eeg_files:
            return None

        for eeg_file in eeg_files:
            bids_sidecar_json = self.bids_layout.get_nearest(
                eeg_file.path,
                return_type = 'tuple',
                strict=False,
                extension = 'json',
                suffix = self.bids_info.data_type,
                all_ = False,
                full_search = False,
            )
            sidecar_json = BidsEegSidecarJsonFile(Path(bids_sidecar_json.path)) if bids_sidecar_json else None

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
            sidecar_json_path = None
            if sidecar_json is not None:
                eeg_file_data = sidecar_json.data

                sidecar_json_path = os.path.relpath(sidecar_json.path, self.data_dir)
                if self.loris_bids_root_dir:
                    # copy the JSON file to the LORIS BIDS import directory
                    sidecar_json_path = self.copy_file_to_loris_bids_dir(
                        sidecar_json.path, derivatives
                    )

                eeg_file_data['eegjson_file'] = sidecar_json_path
                json_blake2 = compute_file_blake2b_hash(sidecar_json.path)
                eeg_file_data['physiological_json_file_blake2b_hash'] = json_blake2

            eeg_file_path = Path(eeg_file.path)

            # greps the file type from the ImagingFileTypes table
            file_type = get_check_bids_imaging_file_type_from_extension(self.env, eeg_file_path)

            # grep the output type from the physiological_output_type table
            output_type = get_check_bids_physio_output_type(self.env, 'derivative' if derivatives else 'raw')

            # get the acquisition date of the EEG file or the age at the time of the EEG recording
            eeg_acq_time = None
            if self.scans_file is not None:
                scan_info = self.scans_file.get_row(eeg_file_path)
                if scan_info is not None:
                    try:
                        eeg_acq_time = scan_info.get_acquisition_time()
                        eeg_file_data['age_at_scan'] = scan_info.get_age_at_scan()
                    except Exception as error:
                        print(f"ERROR: {error}")
                        sys.exit(lib.exitcode.PROGRAM_EXECUTION_FAILURE)

                    if self.loris_bids_root_dir:
                        # copy the scans.tsv file to the LORIS BIDS import directory
                        scans_path = copy_scans_tsv_file_to_loris_bids_dir(
                            self.scans_file,
                            self.bids_info.subject,
                            self.loris_bids_root_dir,
                            self.data_dir,
                        )

                    eeg_file_data['scans_tsv_file'] = scans_path
                    scans_blake2 = compute_file_blake2b_hash(self.scans_file.path)
                    eeg_file_data['physiological_scans_tsv_file_bake2hash'] = scans_blake2

            # if file type is set and fdt file exists, append fdt path to the
            # eeg_file_data dictionary
            fdt_file_path = None
            if file_type.name == 'set' and fdt_file:
                fdt_file_path = os.path.relpath(fdt_file, self.data_dir)
                if self.loris_bids_root_dir:
                    # copy the fdt file to the LORIS BIDS import directory
                    fdt_file_path = self.copy_file_to_loris_bids_dir(
                        fdt_file.path, derivatives
                    )

                eeg_file_data['fdt_file'] = fdt_file_path
                fdt_blake2 = compute_file_blake2b_hash(fdt_file.path)
                eeg_file_data['physiological_fdt_file_blake2b_hash'] = fdt_blake2

            # check that the file is not already inserted before inserting it
            eeg_path = os.path.relpath(eeg_file.path, self.data_dir)
            loris_eeg_file = try_get_physio_file_with_path(self.env.db, Path(eeg_path))
            if loris_eeg_file is not None:
                log(self.env, f"Skipping already inserted file '{eeg_path}'.")
                continue

            # append the blake2b to the eeg_file_data dictionary
            blake2 = get_check_bids_physio_file_hash(self.env, Path(eeg_file.path))
            eeg_file_data['physiological_file_blake2b_hash'] = blake2

            # grep the modality ID from physiological_modality table
            modality = get_check_bids_physio_modality(self.env, self.bids_info.data_type)

            if self.loris_bids_root_dir:
                # copy the eeg_file to the LORIS BIDS import directory
                eeg_path = self.copy_file_to_loris_bids_dir(
                    eeg_file.path, derivatives
                )

            # insert the file along with its information into
            # physiological_file and physiological_parameter_file tables
            physio_file = insert_physio_file(
                self.env,
                self.session,
                Path(eeg_path),
                file_type,
                modality,
                output_type,
                eeg_acq_time
            )

            insert_physio_file_parameters(self.env, physio_file, eeg_file_data)
            self.env.db.commit()

            if self.loris_bids_root_dir:
                # If we copy the file in assembly_bids and
                # if the EEG file was a set file, then update the filename for the .set
                # and .fdt files in the .set file so it can find the proper file for
                # visualization and analyses
                if file_type.name == 'set':
                    set_full_path = os.path.join(self.data_dir, physio_file.path)
                    width_fdt_file = True if 'fdt_file' in eeg_file_data.keys() else False

                    file_paths_updated = utilities.update_set_file_path_info(set_full_path, width_fdt_file)
                    if not file_paths_updated:
                        print(f"WARNING: cannot update the set file {physio_file.path} path info")

            inserted_eegs.append({
                'file': physio_file,
                'eegjson_file_path': sidecar_json_path,
                'fdt_file_path': fdt_file_path,
                'original_file_data': eeg_file,
            })

        return inserted_eegs

    def fetch_and_insert_electrode_file(
            self, physiological_file: DbPhysioFile, original_physiological_file_path, derivatives=False):
        """
        Gather electrode file information to insert into
        physiological_electrode. Once all the information has been gathered,
        it will call Physiological.insert_electrode_file that will perform the
        insertion into physiological_electrode, linking it to the
        PhysiologicalFileID already registered.

        :param physiological_file: Physiological file object of the associated
                                      physiological file already inserted into
                                      the physiological_file table
        :param derivatives: True if the electrode file to insert is a derivative file.
                            Set by default to False when inserting raw file.
         :type derivatives: boolean

        :return: electrode file path in the /DATA_DIR/bids_import directory
         :rtype: str
        """

        # load the Physiological object that will be used to insert the
        # physiological data into the database
        physiological = Physiological(self.env, self.db, self.env.verbose)

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
                      "physiological file ID " + str(physiological_file.id)
            print(message)
            return None
        else:
            # maybe several electrode files
            for electrode_file in electrode_files:
                result = physiological.grep_electrode_from_physiological_file_id(
                    physiological_file.id
                )
                if not result:
                    electrode_data = utilities.read_tsv_file(electrode_file.path)
                    electrode_path = os.path.relpath(electrode_file.path, self.data_dir)
                    if self.loris_bids_root_dir:
                        # copy the electrode file to the LORIS BIDS import directory
                        electrode_path = self.copy_file_to_loris_bids_dir(
                            electrode_file.path, derivatives
                        )
                    # get the blake2b hash of the electrode file
                    blake2 = compute_file_blake2b_hash(electrode_file.path)

                    # insert the electrode data in the database
                    electrode_ids = physiological.insert_electrode_file(
                        electrode_data, electrode_path, physiological_file, blake2
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
                        subject=self.bids_info.subject,
                    )
                    if not coordsystem_metadata_file:
                        message = '\nWARNING: no electrode metadata files (coordsystem.json) ' \
                                  f'associated with physiological file ID {physiological_file.id}'
                        print(message)

                        # insert default (not registered) coordsystem in the database
                        physiological.insert_electrode_metadata(
                            None,
                            None,
                            physiological_file,
                            None,
                            electrode_ids
                        )
                    else:
                        electrode_metadata_path = os.path.relpath(coordsystem_metadata_file, self.data_dir)
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
                            physiological_file,
                            blake2,
                            electrode_ids
                        )

    def fetch_and_insert_channel_file(
            self, physiological_file: DbPhysioFile, original_physiological_file_path, derivatives=False):
        """
        Gather channel file information to insert into physiological_channel.
        Once all the information has been gathered, it will call
        Physiological.insert_channel_file that will perform the insertion into
        physiological_channel, linking it to the PhysiologicalFileID already
        registered.

        :param physiological_file:               Physiological file object of the associated
                                                 physiological file already inserted into
                                                 the physiological_file table
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
        physiological = Physiological(self.env, self.db, self.env.verbose)

        bids_channels_file = self.bids_layout.get_nearest(
            original_physiological_file_path,
            return_type = 'tuple',
            strict = False,
            extension = 'tsv',
            suffix = 'channels',
            all_ = False,
            full_search = False,
        )
        channels_file = BidsEegChannelsTsvFile(Path(bids_channels_file.path)) if bids_channels_file else None

        if channels_file is None:
            print(f"WARNING: no channel file associated with physiological file ID {physiological_file.id}")
            return None

        if physiological_file.channels != []:
            return physiological_file.channels[0].file_path

        channel_path = os.path.relpath(channels_file.path, self.data_dir)
        if self.loris_bids_root_dir:
            # copy the channel file to the LORIS BIDS import directory
            channel_path = self.copy_file_to_loris_bids_dir(
                channels_file.path, derivatives
            )
        # get the blake2b hash of the channel file
        blake2 = compute_file_blake2b_hash(channels_file.path)
        # insert the channel data in the database
        physiological.insert_channel_file(
            channels_file, channel_path, physiological_file, blake2
        )

        return channel_path

    def fetch_and_insert_event_files(
            self, physiological_file: DbPhysioFile, original_physiological_file_path, derivatives=False):
        """
        Gather raw channel file information to insert into
        physiological_task_event. Once all the information has been gathered,
        it will call Physiological.insert_event_file that will perform the
        insertion into physiological_task_event, linking it to the
        PhysiologicalFileID already registered.

        :param physiological_file:               Physiological file object of the associated
                                                 physiological file already inserted into
                                                 the physiological_file table
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
        physiological = Physiological(self.env, self.db, self.env.verbose)

        bids_events_data_file = self.bids_layout.get_nearest(
            original_physiological_file_path,
            return_type = 'tuple',
            strict = False,
            extension = 'tsv',
            suffix = 'events',
            all_ = False,
            full_search = False,
        )
        events_data_file = BidsEventsTsvFile(Path(bids_events_data_file.path)) if bids_events_data_file else None

        if events_data_file is None:
            message = "WARNING: no events file associated with " \
                      f"physiological file ID {physiological_file.id}"
            print(message)
            return None
        else:
            event_paths = [event_file.file_path for event_file in physiological_file.event_files]

            file_tag_dict = {}
            if event_paths == []:
                # get events.json file and insert
                # subject-specific metadata
                event_metadata_file = self.bids_layout.get_nearest(
                    events_data_file.path,
                    return_type = 'tuple',
                    strict = False,
                    extension = 'json',
                    suffix = 'events',
                    all_ = False,
                    full_search = False,
                    subject=self.bids_info.subject,
                )
                inheritance = False

                if not event_metadata_file:
                    message = "WARNING: no events metadata files (events.json) associated " \
                              f"with physiological file ID {physiological_file.id}"
                    print(message)
                else:
                    event_metadata_path = os.path.relpath(event_metadata_file.path, self.data_dir)
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
                        physiological_file=physiological_file,
                        project_id=self.session.project.id,
                        blake2=blake2,
                        project_wide=False,
                        hed_union=self.hed_union
                    )
                    event_paths.extend([event_metadata_path])

            # get events.tsv file and insert
            event_path = os.path.relpath(events_data_file.path, self.data_dir)
            if self.loris_bids_root_dir:
                # copy the event file to the LORIS BIDS import directory
                event_path = self.copy_file_to_loris_bids_dir(
                    events_data_file.path, derivatives
                )
            # get the blake2b hash of the task events file
            blake2 = compute_file_blake2b_hash(events_data_file.path)

            # insert event data in the database
            physiological.insert_event_file(
                events_file=events_data_file,
                event_file=event_path,
                physiological_file=physiological_file,
                project_id=self.session.project.id,
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
            copy_file = os.path.relpath(file, self.bids_layout.root)
            copy_file = os.path.join(self.loris_bids_root_dir, copy_file)
        else :
            # determine the path of the copied file
            copy_file = ""
            if not inheritance:
                copy_file = self.loris_bids_eeg_rel_dir
            if self.bids_info.session is not None:
                copy_file = os.path.join(copy_file, os.path.basename(file))
            else:
                # make sure the ses- is included in the new filename if using
                # default visit label from the LORIS config
                copy_file = os.path.join(
                    copy_file,
                    os.path.basename(file).replace(
                        f'sub-{self.bids_info.subject}',
                        f'sub-{self.bids_info.subject}_ses-{self.session.visit_label}'
                    )
                )

            copy_file = os.path.join(self.loris_bids_root_dir, copy_file)

        # create the directory if it does not exist
        lib.utilities.create_dir(
            os.path.dirname(copy_file),
            self.env.verbose
        )

        # copy the file
        utilities.copy_file(file, copy_file, self.env.verbose)

        # determine the relative path and return it
        relative_path = os.path.relpath(copy_file, self.data_dir)

        return relative_path

    def create_and_insert_archive(self, files_to_archive: list[str], archive_rel_name: str, eeg_file: DbPhysioFile):
        """
        Create an archive with all electrophysiology files associated to a
        specific recording (including electrodes.tsv, channels.tsv etc...)
        :param files_to_archive: list of files to include in the archive
        :param archive_rel_name: path to the archive relative to data_dir
        :param eeg_file_id     : PhysiologicalFileID
        """

        # load the Physiological object that will be used to insert the
        # physiological archive into the database
        physiological = Physiological(self.env, self.db, self.env.verbose)

        # check if archive is on the filesystem
        (archive_rel_name, archive_full_path) = self.get_archive_paths(archive_rel_name)
        if os.path.isfile(archive_full_path):
            blake2 = compute_file_blake2b_hash(archive_full_path)
        else:
            blake2 = None

        # check if archive already inserted in database and matches the one
        # on the filesystem using blake2b hash
        if eeg_file.archive is not None:
            if not blake2:
                message = 'ERROR: no archive was found on the filesystem ' + \
                          'while an entry was found in the database for '   + \
                          f'PhysiologicalFileID = {eeg_file.id}'
                print(message)
                exit(lib.exitcode.MISSING_FILES)
            elif eeg_file.archive.blake2b_hash != blake2:
                message = '\nERROR: blake2b hash of ' + archive_full_path     +\
                          ' does not match the one stored in the database.'   +\
                          '\nblake2b of ' + archive_full_path + ': ' + blake2 +\
                          '\nblake2b in the database: ' + eeg_file.archive.blake2b_hash
                print(message)
                exit(lib.exitcode.CORRUPTED_FILE)
            else:
                return

        # create the archive directory if it does not exist
        lib.utilities.create_dir(
            os.path.dirname(archive_full_path),
            self.env.verbose
        )

        # create the archive file
        utilities.create_archive(files_to_archive, archive_full_path)

        # insert the archive file in physiological_archive
        blake2 = compute_file_blake2b_hash(archive_full_path)
        archive_info = {
            'PhysiologicalFileID': eeg_file.id,
            'Blake2bHash'        : blake2,
            'FilePath'           : archive_rel_name
        }
        physiological.insert_archive_file(archive_info)

    def create_and_insert_event_archive(
        self,
        files_to_archive: list[str],
        archive_rel_name: str,
        eeg_file: DbPhysioFile,
    ):
        """
        Create an archive with all event files associated to a specific recording
        :param files_to_archive: list of files to include in the archive
        :param archive_rel_name: path to the archive relative to data_dir
        :param eeg_file     : Physiological file object
        """

        # check if archive is on the filesystem
        (archive_rel_name, archive_full_path) = self.get_archive_paths(archive_rel_name)
        if os.path.isfile(archive_full_path):
            blake2 = compute_file_blake2b_hash(archive_full_path)
        else:
            blake2 = None

        # check if archive already inserted in database and matches the one
        # on the filesystem using blake2b hash
        physiological_event_archive_obj = PhysiologicalEventArchive(self.db, self.env.verbose)

        if eeg_file.event_archive is not None:
            if not blake2:
                message = '\nERROR: no archive was found on the filesystem ' + \
                          'while an entry was found in the database for '   + \
                          'PhysiologicalFileID = ' + str(eeg_file.id)
                print(message)
                exit(lib.exitcode.MISSING_FILES)
            elif eeg_file.event_archive.blake2b_hash != blake2:
                message = '\nERROR: blake2b hash of ' + archive_full_path     +\
                          ' does not match the one stored in the database.'   +\
                          '\nblake2b of ' + archive_full_path + ': ' + blake2 +\
                          '\nblake2b in the database: ' + eeg_file.event_archive.blake2b_hash
                print(message)
                exit(lib.exitcode.CORRUPTED_FILE)
            else:
                return

        # create the archive directory if it does not exist
        lib.utilities.create_dir(
            os.path.dirname(archive_full_path),
            self.env.verbose
        )

        # create the archive file
        utilities.create_archive(files_to_archive, archive_full_path)

        # insert the archive into the physiological_annotation_archive table
        blake2 = compute_file_blake2b_hash(archive_full_path)
        physiological_event_archive_obj.insert(eeg_file.id, blake2, archive_rel_name)

    def get_archive_paths(self, archive_rel_name):
        package_path = get_eeg_pre_package_download_dir_path_config(self.env)
        if package_path:
            raw_package_dir = os.path.join(package_path, 'raw')
            os.makedirs(raw_package_dir, exist_ok=True)
            archive_rel_name = os.path.basename(archive_rel_name)
            archive_full_path = os.path.join(raw_package_dir, archive_rel_name)
        else:
            archive_full_path = os.path.join(self.data_dir, archive_rel_name)

        return (archive_rel_name, archive_full_path)

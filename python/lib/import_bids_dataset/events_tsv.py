from datetime import datetime, timedelta
from decimal import Decimal

from loris_bids_reader.dataset import BidsAcquisition
from loris_bids_reader.files.events import BidsEventsTsvFile

from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.session import DbSession
from lib.env import Env
from lib.import_bids_dataset.copy_files import get_loris_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.physio.events import insert_physio_event_task, insert_physio_events_file


def insert_bids_events_file(
    env: Env,
    import_env: BidsImportEnv,
    physio_file: DbPhysioFile,
    session: DbSession,
    acquisition: BidsAcquisition,
    events_file: BidsEventsTsvFile,
    # blake2,
    # dataset_tag_dict,
    # file_tag_dict,
    # hed_union,
):
    """
    Inserts the event information read from the file *events.tsv
    into the physiological_task_event table, linking it to the
    physiological file ID already inserted in physiological_file.
    Only called in `eeg.py`.

    :param event_data           : list with dictionaries of events
                                    information to insert into
                                    physiological_task_event
        :type event_data           : list
    :param event_file           : name of the event file
        :type event_file           : str
    :param physiological_file_id: PhysiologicalFileID to link the event info to
        :type physiological_file_id: int
    :param project_id           : ProjectID to link the event info to
        :type project_id           : int
    :param blake2               : blake2b hash of the task event file
        :type blake2               : str
    :param dataset_tag_dict     : Dict of dataset-inherited HED tags
        :type dataset_tag_dict     : dict
    :param file_tag_dict        : Dict of subject-inherited HED tags
        :type file_tag_dict        : dict
    :param hed_union            : Union of HED schemas
        :type hed_union            : any
    """

    loris_events_file_path = get_loris_file_path(import_env, session, acquisition, events_file.path)
    physio_events_file = insert_physio_events_file(env, physio_file, loris_events_file_path)

    print(f"DEBUG: Event file inserted with ID {physio_events_file.id}")

    for row in events_file.rows:
        physio_task_event = insert_physio_event_task(
            env,
            physio_file,
            physio_events_file,
            Decimal(row.data['onset']),
            Decimal(row.data['duration']),
            row.data['trial_type'],
            (
                (datetime(1, 1, 1) + timedelta(seconds=row.data['response_time'])).time()
                if row.data['response_time'] is not None
                else None
            ),
        )

        # TODO: Handle HED.

        print(f"DEBUG: Event task inserted with ID {physio_task_event.id}")

from dataclasses import dataclass
from datetime import datetime, time
from decimal import Decimal
from pathlib import Path

from lib.db.models.physio_event_file import DbPhysioEventFile
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_task_event import DbPhysioTaskEvent
from lib.env import Env


@dataclass
class DatasetSource:
    project_id: int

    @property
    def physio_file(self) -> None:
        return None

    @property
    def physio_file_id(self) -> None:
        return None

    @property
    def project_wide(self) -> bool:
        return True


@dataclass
class FileSource:
    physio_file: DbPhysioFile

    @property
    def project_id(self) -> int:
        return self.physio_file.session.project.id

    @property
    def physio_file_id(self) -> int:
        return self.physio_file.id

    @property
    def project_wide(self) -> bool:
        return False


EventFileSource = DatasetSource | FileSource


def insert_physio_events_dictionary_file(env: Env):
    pass


def insert_physio_events_file(env: Env, physio_file: DbPhysioFile, path: Path) -> DbPhysioEventFile:
    """
    Insert a physiological events file into the database.
    """

    event_file = DbPhysioEventFile(
        physio_file_id = physio_file.id,
        project_id     = physio_file.session.project.id,
        file_type      = 'tsv',
        file_path      = path,
    )

    env.db.add(event_file)
    env.db.flush()

    return event_file


def insert_physio_event_task(
    env: Env,
    physio_file: DbPhysioFile,
    events_file: DbPhysioEventFile,
    onset: Decimal,
    duration: Decimal,
    trial_type: str | None,
    response_time: time | None,
) -> DbPhysioTaskEvent:
    """
    Insert a physiological event task in the database.
    """

    event_task_file = DbPhysioTaskEvent(
        physio_file_id = physio_file.id,
        event_file_id  = events_file.id,
        insert_time    = datetime.now(),
        onset          = onset,
        duration       = duration,
        event_code     = 0,  # row.event_code TODO: This seems to be a non-standard field.
        event_value    = '',  # row.trial_type TODO: This seems to be a non-standard field.
        event_sample   = Decimal(0),  # row.event_sample TODO: This seems to be a non-standard field.
        event_type     = '',  # row.event_type TODO: This seems to be a non-standard field.
        trial_type     = trial_type,
        response_time  = response_time,
    )

    # TODO: Handle HED.

    env.db.add(event_task_file)
    env.db.flush()

    return event_task_file

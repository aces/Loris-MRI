import getpass
from datetime import datetime
from pathlib import Path

from lib.db.models.imaging_file_type import DbImagingFileType
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_modality import DbPhysioModality
from lib.db.models.physio_output_type import DbPhysioOutputType
from lib.db.models.session import DbSession
from lib.env import Env


def insert_physio_file(
    env: Env,
    session: DbSession,
    file_path: Path,
    file_type: DbImagingFileType,
    modality: DbPhysioModality,
    output_type: DbPhysioOutputType,
    acquisition_time: datetime | None,
) -> DbPhysioFile:
    """
    Insert a physiological file into the database.
    """

    file = DbPhysioFile(
        path             = file_path,
        type             = file_type.name,
        session_id       = session.id,
        modality_id      = modality.id,
        output_type_id   = output_type.id,
        acquisition_time = acquisition_time,
        inserted_by_user = getpass.getuser(),
    )

    env.db.add(file)
    env.db.flush()
    return file

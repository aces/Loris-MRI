from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.parameter_type import DbParameterType
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_file_parameter import DbPhysioFileParameter


def try_get_physio_file_with_path(db: Database, path: Path) -> DbPhysioFile | None:
    """
    Get a physiological file from the database using its path, or return `None` if no file was
    found.
    """

    return db.execute(select(DbPhysioFile)
        .where(DbPhysioFile.path == path)
    ).scalar_one_or_none()


def try_get_physio_file_with_hash(db: Database, file_hash: str) -> DbPhysioFile | None:
    """
    Get a physiological file from the database using its BLAKE2b hash, or return `None` if no
    physiological file is found.
    """

    return db.execute(select(DbPhysioFile)
        .join(DbPhysioFile.parameters)
        .join(DbPhysioFileParameter.type)
        .where(
            DbParameterType.name == 'physiological_json_file_blake2b_hash',
            DbPhysioFileParameter.value == file_hash,
        )
    ).scalar_one_or_none()

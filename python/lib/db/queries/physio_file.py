from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.parameter_type import DbParameterType
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_file_parameter import DbPhysioFileParameter


def try_get_physio_file_with_path(db: Database, path: str) -> DbPhysioFile | None:
    """
    Get a physiological file from the database using its path, or return `None` if no file was
    found.
    """

    return db.execute(select(DbPhysioFile)
        .where(DbPhysioFile.path == path)
    ).scalar_one_or_none()


def get_physio_file_parameters(
    db: Database,
    physio_file_id: int,
) -> Sequence[tuple[DbParameterType, DbPhysioFileParameter]]:
    """
    Get the parameters of a physiological file using its ID.
    """

    return db.execute(select(DbParameterType, DbPhysioFileParameter)
        .join(DbPhysioFileParameter.type)
        .where(DbPhysioFileParameter.file_id == physio_file_id)
    ).tuples().all()

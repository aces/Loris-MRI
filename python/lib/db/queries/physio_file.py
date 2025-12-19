from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.physio_file import DbPhysioFile


def try_get_physio_file_with_path(db: Database, path: Path) -> DbPhysioFile | None:
    """
    Get a physiological file from the database using its path, or return `None` if no file was
    found.
    """

    return db.execute(select(DbPhysioFile)
        .where(DbPhysioFile.path == path)
    ).scalar_one_or_none()

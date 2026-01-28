from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.imaging_file_type import DbImagingFileType


def get_all_imaging_file_types(db: Database) -> Sequence[DbImagingFileType]:
    """
    Get a sequence of all imaging file types from the database.
    """

    return db.execute(select(DbImagingFileType)).scalars().all()


def try_get_imaging_file_type_with_type(db: Database, type: str) -> DbImagingFileType | None:
    """
    Get an imaging file type from the database using its type, or return `None` if no imaging file
    type is found.
    """

    return db.execute(select(DbImagingFileType)
        .where(DbImagingFileType.type == type)
    ).scalar_one_or_none()

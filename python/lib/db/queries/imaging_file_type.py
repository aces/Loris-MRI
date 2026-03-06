from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.imaging_file_type import DbImagingFileType


def try_get_imaging_file_type_with_name(db: Database, name: str) -> DbImagingFileType | None:
    """
    Get an imaging file type from the database using its name, or return `None` if no imaging file
    type is found.
    """

    return db.execute(select(DbImagingFileType)
        .where(DbImagingFileType.name == name)
    ).scalar_one_or_none()

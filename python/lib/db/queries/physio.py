from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.physio_modality import DbPhysioModality
from lib.db.models.physio_output_type import DbPhysioOutputType


def try_get_physio_modality_with_name(db: Database, name: str) -> DbPhysioModality | None:
    """
    Get a physiological modality from the database using its name, or return `None` if no modality
    was found.
    """

    return db.execute(select(DbPhysioModality)
        .where(DbPhysioModality.name == name)
    ).scalar_one_or_none()


def try_get_physio_output_type_with_name(db: Database, name: str) -> DbPhysioOutputType | None:
    """
    Get a physiological output type from the database using its name, or return `None` if no
    output type was found.
    """

    return db.execute(select(DbPhysioOutputType)
        .where(DbPhysioOutputType.name == name)
    ).scalar_one_or_none()

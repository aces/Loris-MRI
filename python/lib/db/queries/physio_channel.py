from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.physio_channel_type import DbPhysioChannelType
from lib.db.models.physio_status_type import DbPhysioStatusType


def try_get_channel_type_with_name(db: Database, name: str) -> DbPhysioChannelType | None:
    """
    Get a physiological channel type from the database using its name, or return `None` if no
    physiological channel type is found.
    """

    return db.execute(select(DbPhysioChannelType)
        .where(DbPhysioChannelType.name == name)
    ).scalar_one_or_none()


def try_get_status_type_with_name(db: Database, name: str) -> DbPhysioStatusType | None:
    """
    Get a physiological status type from the database using its name, or return `None` if no
    physiological status type is found.
    """

    return db.execute(select(DbPhysioStatusType)
        .where(DbPhysioStatusType.name == name)
    ).scalar_one_or_none()

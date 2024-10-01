from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.model.notification_type import DbNotificationType


def get_notification_type_with_name(db: Database, name: str):
    """
    Get a notification type from the database using its configuration setting name, or raise an
    exception if no notification type is found.
    """

    return db.execute(select(DbNotificationType)
        .where(DbNotificationType.name == name)
    ).scalar_one()

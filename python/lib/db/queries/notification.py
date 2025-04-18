from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.notification_type import DbNotificationType


def try_get_notification_type_with_name(db: Database, name: str) -> DbNotificationType | None:
    """
    Get a notification type from the database using its configuration setting name, or return
    `None` if no notification type is found.
    """

    return db.execute(select(DbNotificationType)
        .where(DbNotificationType.name == name)
    ).scalar_one_or_none()

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.user import DbUser


def try_get_user_with_id(db: Database, user_id: int) -> DbUser | None:
    """
    Get a user from the database using its ID, or return `None` if no user is found.
    """

    return db.execute(select(DbUser)
        .where(DbUser.id == user_id)
    ).scalar_one_or_none()


def try_get_user_with_username(db: Database, username: str) -> DbUser | None:
    """
    Get a user from the database using its username, or return `None` if no user is found.
    """

    return db.execute(select(DbUser)
        .where(DbUser.username == username)
    ).scalar_one_or_none()

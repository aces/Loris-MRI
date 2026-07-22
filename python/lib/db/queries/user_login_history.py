from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session as Database

from lib.db.models.user_login_history import DbUserLoginHistory


def try_get_last_successful_login_time(db: Database, username: str) -> datetime | None:
    """
    Get the time of a user's last successful login, or return `None` if none is recorded.
    """

    return db.execute(select(func.max(DbUserLoginHistory.login_timestamp))
        .where(DbUserLoginHistory.username == username)
        .where(DbUserLoginHistory.success == True)
    ).scalar_one()


def count_failed_logins_since(db: Database, username: str, ip_address: str, start_time: datetime) -> int:
    """
    Count failed logins for a user and client IP after a given time.
    """

    return db.execute(select(func.count(DbUserLoginHistory.id))
        .where(DbUserLoginHistory.username == username)
        .where(DbUserLoginHistory.ip_address == ip_address)
        .where(DbUserLoginHistory.success == False)
        .where(DbUserLoginHistory.login_timestamp > start_time)
    ).scalar_one()

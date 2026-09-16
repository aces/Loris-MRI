from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session as Database


def get_database_time(db: Database) -> datetime:
    """
    Get the current time from the database server.
    """

    return db.execute(select(func.now())).scalar_one()

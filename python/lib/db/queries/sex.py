from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.sex import DbSex


def try_get_sex_with_name(db: Database, name: str) -> DbSex | None:
    """
    Try to get a sex from the database using its name, or return `None` if no sex is found.
    """

    return db.execute(select(DbSex)
        .where(DbSex.name == name)
    ).scalar_one_or_none()

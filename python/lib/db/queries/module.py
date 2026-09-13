from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.module import DbModule


def try_get_module_with_name(db: Database, name: str) -> DbModule | None:
    """
    Get a module using its name, or return `None` if no module is found.
    """

    return db.execute(select(DbModule)
        .where(DbModule.name == name)
    ).scalar_one_or_none()

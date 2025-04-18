from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.file_parameter import DbFileParameter


def try_get_file_parameter_with_file_id_type_id(db: Database, file_id: int, type_id: int) -> DbFileParameter | None:
    """
    Get a file parameter from the database using its file ID and type ID, or return `None` if no
    file parameter is found.
    """

    return db.execute(select(DbFileParameter)
        .where(DbFileParameter.type_id == type_id)
        .where(DbFileParameter.file_id == file_id)
    ).scalar_one_or_none()

from sqlalchemy import delete
from sqlalchemy.orm import Session as Database

from lib.db.models.file_parameter import DbFileParameter


def delete_file_parameter(db: Database, file_parameter_id: int):
    """
    Delete from the database a parameter value based on a file ID and parameter ID.
    """

    db.execute(delete(DbFileParameter)
        .where(DbFileParameter.id == file_parameter_id))

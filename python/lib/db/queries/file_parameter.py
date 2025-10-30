from sqlalchemy import delete, select
from sqlalchemy.orm import Session as Database

from lib.db.models.file_parameter import DbFileParameter
from lib.db.models.parameter_type import DbParameterType


def delete_file_parameter(db: Database, file_parameter_id: int):
    """
    Delete from the database a parameter value based on a file ID and parameter ID.
    """

    db.execute(delete(DbFileParameter)
        .where(DbFileParameter.id == file_parameter_id))


def try_get_parameter_value_with_file_id_parameter_name(
    db: Database,
    file_id: int,
    parameter_name: str
) -> DbFileParameter | None:
    """
    Get parameter value from file ID and parameter name, or return `None` if no entry was found
    """

    return db.execute(select(DbFileParameter)
        .join(DbFileParameter.type)
        .where(DbParameterType.name == parameter_name)
        .where(DbFileParameter.file_id == file_id)
    ).scalar_one_or_none()


def try_get_file_parameter_with_file_id_type_id(db: Database, file_id: int, type_id: int) -> DbFileParameter | None:
    """
    Get a file parameter from the database using its file ID and type ID, or return `None` if no
    file parameter is found.
    """

    return db.execute(select(DbFileParameter)
        .where(DbFileParameter.type_id == type_id)
        .where(DbFileParameter.file_id == file_id)
    ).scalar_one_or_none()

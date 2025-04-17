from sqlalchemy import delete, select
from sqlalchemy.orm import Session as Database

from lib.db.models.file import DbFile
from lib.db.models.file_parameter import DbFileParameter
from lib.db.models.parameter_type import DbParameterType


def try_get_file_with_unique_combination(
    db: Database,
    series_uid: str,
    echo_time: str | None,
    echo_number: str | None,
    phase_encoding_direction: str | None
) -> DbFile | None:
    """
    Get a file from the database using its SeriesInstanceUID, or return `None` if
    no file was found.
    """

    return db.execute(select(DbFile)
        .where(DbFile.series_uid == series_uid)
        .where(DbFile.echo_time == echo_time)
        .where(DbFile.echo_number == echo_number)
        .where(DbFile.phase_encoding_direction == phase_encoding_direction)
    ).scalar_one_or_none()


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


def try_get_file_with_hash(db: Database, file_hash: str) -> DbFile | None:
    """
    Get an imaging file from the database using its BLAKE2b or MD5 hash, or return `None` if no
    imaging file is found.
    """

    return db.execute(select(DbFile)
        .join(DbFile.parameters)
        .join(DbFileParameter.type)
        .where(DbParameterType.name.in_(['file_blake2b_hash', 'md5hash']))
        .where(DbFileParameter.value == file_hash)
    ).scalar_one_or_none()


def delete_file(db: Database, file_id: int):
    """
    Delete from the database a file entry based on a file ID.
    """

    db.execute(delete(DbFile)
       .where(DbFile.id == file_id))

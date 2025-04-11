from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.file import DbFile
from lib.db.models.parameter_file import DbParameterFile
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
) -> DbParameterFile | None:
    """
    Get parameter value from file ID and parameter name, or return `None` if no entry was found
    """

    return db.execute(select(DbParameterFile)
        .join(DbParameterFile.type)
        .where(DbParameterType.name == parameter_name)
        .where(DbParameterFile.file_id == file_id)
    ).scalar_one_or_none()

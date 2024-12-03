from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.parameter_type import DbParameterType
from lib.db.models.physio_file_parameter import DbPhysioFileParameter
from lib.db.queries.parameter_type import try_get_parameter_type_with_name_source


def try_get_physio_parameter_type_with_name(
    db: Database,
    name: str
) -> DbParameterType | None:
    """
    Try to get a physiological parameter type using its name, or return `None` if no physiological
    parameter is found.
    """

    return try_get_parameter_type_with_name_source(db, name, 'physiological_file')


def try_get_physio_file_parameter_with_file_id_type_id(
    db: Database,
    file_id: int,
    type_id: int,
) -> DbPhysioFileParameter | None:
    """
    Get a physiological file parameter from the database using its file ID and type ID, or return
    `None` if no physiological file parameter is found.
    """

    return db.execute(select(DbPhysioFileParameter)
        .where(
            DbPhysioFileParameter.type_id == type_id,
            DbPhysioFileParameter.file_id == file_id,
        )
    ).scalar_one_or_none()


def try_get_physio_file_parameter_with_file_id_name(
    db: Database,
    file_id: int,
    name: str,
) -> DbPhysioFileParameter | None:
    """
    Try to get a physiological file parameter using its file ID and parameter type name, or return
    `None` if no parameter is found.
    """

    parameter_type = try_get_physio_parameter_type_with_name(db, name)
    if parameter_type is None:
        return None

    return try_get_physio_file_parameter_with_file_id_type_id(db, file_id, parameter_type.id)


def get_physio_file_parameters(
    db: Database,
    physio_file_id: int,
) -> Sequence[tuple[DbParameterType, DbPhysioFileParameter]]:
    """
    Get the parameters of a physiological file using its ID.
    """

    return db.execute(select(DbParameterType, DbPhysioFileParameter)
        .join(DbPhysioFileParameter.type)
        .where(DbPhysioFileParameter.file_id == physio_file_id)
    ).tuples().all()

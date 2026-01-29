import getpass
from datetime import datetime
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session as Database

from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_file_parameter import DbPhysioFileParameter
from lib.db.models.physio_modality import DbPhysioModality
from lib.db.models.physio_output_type import DbPhysioOutputType
from lib.db.models.session import DbSession
from lib.db.queries.physio_parameter import (
    get_physio_file_parameters,
    try_get_physio_file_parameter_with_file_id_type_id,
)
from lib.env import Env
from lib.imaging_lib.parameter import get_or_create_parameter_type


def get_physio_file_parameters_dict(db: Database, physio_file_id: int) -> dict[str, str | None]:
    """
    Get the parameters of a physiological file as a dictionary mapping from the name of the
    parameters to their values.
    """

    parameters = get_physio_file_parameters(db, physio_file_id)
    return {
        parameter_type.name: parameter.value for parameter_type, parameter in parameters
    }


def insert_physio_file(
    env: Env,
    session: DbSession,
    modality: DbPhysioModality,
    output_type: DbPhysioOutputType,
    file_path: Path,
    file_type: str,
    acquisition_time: datetime | None,
) -> DbPhysioFile:
    file = DbPhysioFile(
        path             = file_path,
        type             = file_type,
        session_id       = session.id,
        modality_id      = modality.id,
        output_type_id   = output_type.id,
        acquisition_time = acquisition_time,
        inserted_by_user = getpass.getuser(),
    )

    env.db.add(file)
    env.db.flush()
    return file


def insert_physio_file_parameter(
    env: Env,
    file: DbPhysioFile,
    parameter_name: str,
    parameter_value: Any,
) -> DbPhysioFileParameter:
    """
    Insert or upate a file parameter with the provided parameter name and value.
    """

    if isinstance(parameter_value, list):
        parameter_values = map(lambda parameter_value: str(parameter_value), parameter_value)  # type: ignore
        parameter_value = f"[{', '.join(parameter_values)}]"

    parameter_type = get_or_create_parameter_type(
        env,
        parameter_name,
        'Electrophysiology Variables',
        'physiological_parameter_file',
    )

    parameter = try_get_physio_file_parameter_with_file_id_type_id(env.db, file.id, parameter_type.id)
    if parameter is None:
        parameter = DbPhysioFileParameter(
            file_id    = file.id,
            project_id = file.session.project.id,
            type_id    = parameter_type.id,
            value      = parameter_value,
        )

        env.db.add(parameter)
    else:
        parameter.value = parameter_value

    return parameter

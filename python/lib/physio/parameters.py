from typing import Any

from sqlalchemy.orm import Session as Database

from lib.db.models.parameter_type import DbParameterType
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_file_parameter import DbPhysioFileParameter
from lib.db.queries.physio_parameter import get_physio_file_parameters
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


def get_or_create_physio_parameter_type(env: Env, parameter_name: str) -> DbParameterType:
    """
    Get or create a physiological parameter type with the provided name.
    """

    return get_or_create_parameter_type(
        env,
        parameter_name,
        'Electrophysiology Variables',
        'physiological_parameter_file',
    )


def insert_physio_project_parameter(
    env: Env,
    project_id: int,
    parameter_name: str,
    parameter_value: Any,
) -> DbPhysioFileParameter:
    """
    Insert a physiological project parameter with the provided parameter name and value.
    """

    parameter_type = get_or_create_physio_parameter_type(env, parameter_name)

    parameter = DbPhysioFileParameter(
        project_id = project_id,
        type_id    = parameter_type.id,
        value      = str(parameter_value),
    )

    env.db.add(parameter)
    env.db.flush()

    return parameter


def insert_physio_file_parameters(env: Env, file: DbPhysioFile, parameters: dict[str, Any]):
    """
    Insert or update the parameters for a physiological file.
    """

    for name, value in parameters.items():
        insert_physio_file_parameter(env, file, name, value)


def insert_physio_file_parameter(
    env: Env,
    file: DbPhysioFile,
    parameter_name: str,
    parameter_value: Any,
) -> DbPhysioFileParameter:
    """
    Insert a physiological file parameter with the provided parameter name and value.
    """

    parameter_type = get_or_create_physio_parameter_type(env, parameter_name)

    parameter = DbPhysioFileParameter(
        file_id    = file.id,
        project_id = file.session.project.id,
        type_id    = parameter_type.id,
        value      = str(parameter_value),
    )

    env.db.add(parameter)
    env.db.flush()

    return parameter

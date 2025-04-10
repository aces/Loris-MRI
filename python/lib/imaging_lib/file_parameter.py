from datetime import datetime
from typing import Any

from lib.db.models.file import DbFile
from lib.db.models.file_parameter import DbFileParameter
from lib.db.queries.file_parameter import try_get_file_parameter_with_file_id_type_id
from lib.db.queries.parameter_type import get_parameter_type_with_name
from lib.env import Env


def register_file_parameters(env: Env, file: DbFile, parameter_infos: dict[str, Any]):
    """
    Insert or upate some file parameters with the provided parameter names and values.
    """

    for parameter_name, parameter_value in parameter_infos.items():
        register_file_parameter(env, file, parameter_name, parameter_value)


def register_file_parameter(env: Env, file: DbFile, parameter_name: str, parameter_value: Any):
    """
    Insert or upate a file parameter with the provided parameter name and value.
    """

    if type(parameter_value) is list:
        parameter_values = map(lambda parameter_value: str(parameter_value), parameter_value)  # type: ignore
        parameter_value = f"[{', '.join(parameter_values)}]"

    parameter_type = get_parameter_type_with_name(env.db, parameter_name)

    parameter = try_get_file_parameter_with_file_id_type_id(env.db, file.id, parameter_type.id)
    if parameter is None:
        parameter = DbFileParameter(
            type_id     = parameter_type.id,
            file_id     = file.id,
            value       = parameter_value,
            insert_time = datetime.now(),
        )

        env.db.add(parameter)
    else:
        parameter.value = parameter_value

    env.db.commit()

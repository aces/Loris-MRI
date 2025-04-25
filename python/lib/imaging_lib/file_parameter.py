from datetime import datetime
from typing import Any

from lib.db.models.file import DbFile
from lib.db.models.file_parameter import DbFileParameter
from lib.db.models.parameter_type import DbParameterType
from lib.db.models.parameter_type_category_rel import DbParameterTypeCategoryRel
from lib.db.queries.file_parameter import try_get_file_parameter_with_file_id_type_id
from lib.db.queries.parameter_type import get_parameter_type_category_with_name, try_get_parameter_type_with_name
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

    if isinstance(parameter_value, list):
        parameter_values = map(lambda parameter_value: str(parameter_value), parameter_value)  # type: ignore
        parameter_value = f"[{', '.join(parameter_values)}]"

    parameter_type = get_or_create_parameter_type(env, parameter_name)

    parameter = try_get_file_parameter_with_file_id_type_id(env.db, file.id, parameter_type.id)
    if parameter is None:
        time = datetime.now()

        parameter = DbFileParameter(
            type_id     = parameter_type.id,
            file_id     = file.id,
            value       = parameter_value,
            insert_time = time,
        )

        env.db.add(parameter)
    else:
        parameter.value = parameter_value

    env.db.commit()


def get_or_create_parameter_type(env: Env, parameter_name: str) -> DbParameterType:
    """
    Get a parameter type using its name, or create that parameter if it does not exist.
    """

    parameter_type = try_get_parameter_type_with_name(env.db, parameter_name)
    if parameter_type is not None:
        return parameter_type

    parameter_type = DbParameterType(
        name        = parameter_name,
        alias       = None,
        data_type   = 'text',
        description = f'{parameter_name} created by the lib.imaging.file_parameter Python module',
        source_from = 'parameter_file',
        queryable   = False,
    )

    env.db.add(parameter_type)
    env.db.commit()

    parameter_type_category = get_parameter_type_category_with_name(env.db, 'MRI Variables')
    parameter_type_category_rel = DbParameterTypeCategoryRel(
        parameter_type_id           = parameter_type.id,
        parameter_type_category_id = parameter_type_category.id,
    )

    env.db.add(parameter_type_category_rel)
    env.db.commit()

    return parameter_type

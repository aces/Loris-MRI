from datetime import datetime
from typing import Any

from lib.db.models.file import DbFile
from lib.db.models.file_parameter import DbFileParameter
from lib.db.queries.file_parameter import try_get_file_parameter_with_file_id_type_id
from lib.db.queries.parameter_type import get_all_parameter_types
from lib.env import Env
from lib.imaging_lib.parameter import get_or_create_parameter_type


def register_mri_file_parameters(env: Env, file: DbFile, file_parameters: dict[str, Any]):
    """
    Insert or upate some MRI file parameters with the provided parameter names and values.
    """

    for parameter_name, parameter_value in file_parameters.items():
        register_mri_file_parameter(env, file, parameter_name, parameter_value)


def register_mri_file_parameter(env: Env, file: DbFile, parameter_name: str, parameter_value: Any):
    """
    Insert or upate an MRI file parameter with the provided parameter name and value.
    """

    if isinstance(parameter_value, list):
        parameter_values = map(lambda parameter_value: str(parameter_value), parameter_value)  # type: ignore
        parameter_value = f"[{', '.join(parameter_values)}]"

    parameter_type = get_or_create_parameter_type(env, parameter_name, 'MRI Variables', 'parameter_file')

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

    env.db.flush()


def get_bids_to_loris_parameter_types_dict(env: Env) -> dict[str, str]:
    """
    Get the BIDS to LORIS parameter type mapping from the database. The keys of the dictionary are
    the BIDS parameter names, and its values are corresponding LORIS parameter names.
    """

    parameter_types = get_all_parameter_types(env.db)

    parameter_types_dict: dict[str, str] = {}
    for parameter_type in parameter_types:
        if parameter_type.alias is None:
            continue

        parameter_types_dict[parameter_type.alias] = parameter_type.name

    return parameter_types_dict


def map_bids_to_loris_file_parameters(env: Env, file_parameters: dict[str, Any]):
    """
    Map the BIDS file parameters obtained from a BIDS JSON sidecar file with the corresponding
    LORIS parameter types. The original BIDS parameters are not removed from the dictionary.
    """

    parameter_types_dict = get_bids_to_loris_parameter_types_dict(env)

    for file_parameter in list(file_parameters.keys()):
        file_parameter_type = parameter_types_dict.get(file_parameter)
        if file_parameter_type is not None:
            file_parameters[file_parameter_type] = file_parameters[file_parameter]

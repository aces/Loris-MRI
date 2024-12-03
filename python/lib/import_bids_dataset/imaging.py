from typing import Any

from lib.db.queries.parameter_type import get_all_parameter_types
from lib.env import Env


def map_bids_param_to_loris_param(env: Env, file_parameters: dict[str, Any]):
    """
    Maps the BIDS parameters found in the BIDS JSON file with the
    parameter type names of LORIS.

    :param file_parameters: dictionary with the list of parameters
                            found in the BIDS JSON file
        :type file_parameters: dict

    :return: returns a dictionary with the BIDS JSON parameter names
                as well as their LORIS equivalent
        :rtype: dict
    """

    parameter_types_mapping = get_bids_to_minc_parameter_types_mapping(env)

    # Map BIDS parameters with the LORIS ones.
    for file_parameter in list(file_parameters.keys()):
        file_parameter_type = parameter_types_mapping.get(file_parameter)
        if file_parameter_type is not None:
            file_parameters[file_parameter_type] = file_parameters[file_parameter]


def get_bids_to_minc_parameter_types_mapping(env: Env) -> dict[str, str]:
    """
    Queries the BIDS to MINC mapping dictionary stored in the paramater_type table and returns a
    dictionary with the BIDS term as keys and the MINC terms as values.

    :return: BIDS to MINC mapping dictionary
        :rtype: dict
    """

    parameter_types = get_all_parameter_types(env.db)

    parameter_types_mapping: dict[str, str] = {}
    for parameter_type in parameter_types:
        if parameter_type.alias is None:
            continue

        parameter_types_mapping[parameter_type.alias] = parameter_type.name

    return parameter_types_mapping

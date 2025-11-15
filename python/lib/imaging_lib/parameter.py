from typing import Literal

from lib.db.models.parameter_type import DbParameterType
from lib.db.models.parameter_type_category_rel import DbParameterTypeCategoryRel
from lib.db.queries.parameter_type import get_parameter_type_category_with_name, try_get_parameter_type_with_name_source
from lib.env import Env


def get_or_create_parameter_type(
    env: Env,
    parameter_name: str,
    category: Literal['Electrophysiology Variables', 'MRI Variables'],
    source: Literal['parameter_file', 'physiological_parameter_file']
) -> DbParameterType:
    """
    Get a parameter type using its name, or create that parameter if it does not exist.
    """

    parameter_type = try_get_parameter_type_with_name_source(env.db, parameter_name, source)
    if parameter_type is not None:
        return parameter_type

    parameter_type = DbParameterType(
        name        = parameter_name,
        alias       = None,
        data_type   = 'text',
        description = f'{parameter_name} created by the lib.imaging.parameter Python module',
        source_from = source,
        queryable   = False,
    )

    env.db.add(parameter_type)
    env.db.flush()

    parameter_type_category = get_parameter_type_category_with_name(env.db, category)
    parameter_type_category_rel = DbParameterTypeCategoryRel(
        parameter_type_id          = parameter_type.id,
        parameter_type_category_id = parameter_type_category.id,
    )

    env.db.add(parameter_type_category_rel)
    env.db.flush()

    return parameter_type

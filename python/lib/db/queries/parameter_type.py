from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.parameter_type import DbParameterType
from lib.db.models.parameter_type_category import DbParameterTypeCategory


def get_all_parameter_types(db: Database) -> Sequence[DbParameterType]:
    """
    Get a sequence of all parameter types from the database.
    """

    return db.execute(select(DbParameterType)).scalars().all()


def try_get_parameter_type_with_name_source(db: Database, name: str, source: str) -> DbParameterType | None:
    """
    Get a parameter type from the database using its name and source, or return `None` if no
    parameter type is found.
    """

    return db.execute(select(DbParameterType)
        .where(
            DbParameterType.name        == name,
            DbParameterType.source_from == source,
        )
    ).scalar_one_or_none()


def get_parameter_type_category_with_name(db: Database, name: str) -> DbParameterTypeCategory:
    """
    Get a parameter type category from the database using its name, or raise an exception if no
    parameter type category is found.
    """

    return db.execute(select(DbParameterTypeCategory)
        .where(DbParameterTypeCategory.name == name)
    ).scalar_one()

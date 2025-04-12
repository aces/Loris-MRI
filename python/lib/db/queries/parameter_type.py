from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.parameter_type import DbParameterType


def get_all_parameter_types(db: Database) -> Sequence[DbParameterType]:
    """
    Get a sequence of all parameter types from the database.
    """

    return db.execute(select(DbParameterType)).scalars().all()

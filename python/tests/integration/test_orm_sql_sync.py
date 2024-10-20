import importlib
from pathlib import Path
from typing import Any

from sqlalchemy import MetaData
from sqlalchemy.dialects.mysql.types import DOUBLE, TINYINT
from sqlalchemy.types import TypeDecorator, TypeEngine

from lib.db.base import Base
from tests.util.database import get_integration_database_engine


def test_orm_sql_sync():
    """
    Test that the SQLAlchemy ORM definitions are in sync with the existing SQL database.
    """

    # Load all the ORM table definitions in the SQLAlchemy schema
    for file in Path('python/lib/db/model').glob('*.py'):
        importlib.import_module(f'lib.db.model.{file.name[:-3]}')

    orm_metadata = Base.metadata

    engine = get_integration_database_engine()
    sql_metadata = MetaData()
    sql_metadata.reflect(engine)

    for orm_table in orm_metadata.sorted_tables:
        print(f'test table: {orm_table.name}')

        # Check that each ORM table has a corresponding SQL table
        sql_table = sql_metadata.tables.get(orm_table.name)
        assert sql_table is not None

        # Check that the ORM and SQL tables have the same columns
        orm_column_names = orm_table.columns.keys().sort()
        sql_column_names = sql_table.columns.keys().sort()
        assert orm_column_names == sql_column_names

        for orm_column in orm_table.columns:
            print(f'  test column: {orm_column.name}')

            # Check that the types of the ORM and SQL column are equal
            # The type comparison is not exact, minor differences are ignored
            sql_column = sql_table.columns[orm_column.name]
            orm_column_python_type = get_orm_python_type(orm_column.type)
            sql_column_python_type = get_sql_python_type(sql_column.type)
            assert orm_column_python_type == sql_column_python_type
            assert orm_column.nullable == sql_column.nullable
            assert orm_column.default == sql_column.default

        print()


def get_orm_python_type(orm_type: TypeEngine[Any]):
    if isinstance(orm_type, TypeDecorator):
        return orm_type.impl.python_type

    return orm_type.python_type


def get_sql_python_type(sql_type: TypeEngine[Any]):
    if isinstance(sql_type, TINYINT) and sql_type.display_width == 1:  # type: ignore
        return bool

    if isinstance(sql_type, DOUBLE):
        return float

    return sql_type.python_type

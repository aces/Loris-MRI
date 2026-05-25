import importlib
import re
from pathlib import Path
from types import FunctionType
from typing import Any

from sqlalchemy import ColumnDefault, DefaultClause, Engine, FetchedValue, MetaData, TextClause
from sqlalchemy.dialects.mysql.types import DOUBLE
from sqlalchemy.schema import DefaultGenerator
from sqlalchemy.types import TypeDecorator, TypeEngine

from lib.db.base import Base
from tests.util.database import get_integration_database_engine


def test_orm_sql_sync():
    """
    Test that the SQLAlchemy ORM definitions are in sync with the existing SQL database.
    """

    # Load all the ORM table definitions in the SQLAlchemy schema
    for file in Path('python/lib/db/models').glob('*.py'):
        importlib.import_module(f'lib.db.models.{file.name[:-3]}')

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
        orm_column_names = sorted(orm_table.columns.keys())
        sql_column_names = sorted(sql_table.columns.keys())
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

            if sql_column.server_default is not None:
                orm_default = get_orm_raw_default(engine, orm_column.type, orm_column.default)
                compare_orm_sql_raw_defaults(orm_default, sql_column.server_default)
            else:
                assert orm_column.default is None

        print()


def get_orm_raw_default(engine: Engine, orm_type: TypeEngine[Any], orm_default: DefaultGenerator | None) -> object:
    """
    Get the default value of an ORM value processed the raw SQL type of its column, that is, after
    being transformed by the eventual type decorator of this column.
    """

    # All ORM column defaults are of the `ColumnDefault` class.
    assert isinstance(orm_default, ColumnDefault | None)

    orm_value = orm_default.arg if orm_default is not None else None

    bind_processor = orm_type.bind_processor(engine.dialect)
    if bind_processor is not None:
        return bind_processor(orm_value)

    return orm_value


def compare_orm_sql_raw_defaults(orm_default: object, sql_default: FetchedValue):
    """
    Compare the raw default value of an ORM column with that of an SQL column.
    """

    # All SQL defaults are of the `DefaultClause` class, carrying a `TextClause` value.
    assert isinstance(sql_default, DefaultClause) and isinstance(sql_default.arg, TextClause)

    # The SQL default values are stored as raw strings independently of their shape.
    sql_text = sql_default.arg.text

    # If the SQL default has an on update part, ignore it.
    sql_update_match = re.match(r'(.+) ON UPDATE .+$', sql_text)
    if sql_update_match is not None:
        sql_text = sql_update_match.group(1)

    # If the SQL default is the current timestamp, ensure the ORM default is `datetime.now`.
    if sql_text == 'current_timestamp()':
        # For some reason, direct function comparison does not work, use the function name instead.
        assert isinstance(orm_default, FunctionType) and orm_default.__qualname__ == 'datetime.now'
        return

    # If the SQL default is a string literal, ensure the ORM default is the same string.
    sql_string_match = re.match(r'\'(.*)\'$', sql_text)
    if sql_string_match is not None:
        assert orm_default == sql_string_match.group(1)
        return

    # Otherwise, ensure the textual values are equal.
    assert str(orm_default) == sql_text


def get_orm_python_type(orm_type: TypeEngine[Any]):
    """
    Get the Python type of an ORM column.
    """

    if isinstance(orm_type, TypeDecorator):
        return orm_type.impl.python_type

    return orm_type.python_type


def get_sql_python_type(sql_type: TypeEngine[Any]):
    """
    Get the Python type of an SQL column.
    """

    if isinstance(sql_type, DOUBLE):
        return float

    return sql_type.python_type

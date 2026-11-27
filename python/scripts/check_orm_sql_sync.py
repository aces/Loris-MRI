#!/usr/bin/env python

"""Check that ORM table definitions match the configured SQL database."""

import argparse
import importlib
import pkgutil
import re
from dataclasses import dataclass
from types import FunctionType
from typing import cast

from sqlalchemy import Column, ColumnDefault, DefaultClause, FetchedValue, MetaData, Table, TextClause
from sqlalchemy.dialects.mysql.types import DOUBLE
from sqlalchemy.schema import DefaultGenerator
from sqlalchemy.types import TypeDecorator, TypeEngine

import lib.db.models
import lib.exitcode
from lib.config_file import load_config
from lib.db.base import Base
from lib.env import Env
from lib.logging import log, log_error_exit, log_verbose
from lib.make_env import make_env


@dataclass(frozen=True)
class SchemaDifference:
    """
    Difference between the ORM metadata and the reflected SQL database schema.
    """

    table: str
    column: str | None
    message: str


def main():
    parser = argparse.ArgumentParser(
        description="Check that ORM model definitions match the configured SQL database.",
    )

    parser.add_argument(
        '-p', '--profile',
        help="Name of the python database config file in the config directory."
    )

    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help="If set, be verbose."
    )

    args = parser.parse_args()

    config_file = load_config(args.profile)
    env = make_env('check-orm-sql-sync', args, config_file, args.verbose)

    differences = check_orm_sql_sync(env)
    if differences:
        log_error_exit(
            env,
            (
                f"ORM/SQL schema sync check failed with {len(differences)} difference(s).\n"
                f"{format_schema_differences(differences)}"
            ),
            lib.exitcode.PROGRAM_EXECUTION_FAILURE,
        )

    log(env, "ORM/SQL schema sync check passed.")


def check_orm_sql_sync(env: Env) -> list[SchemaDifference]:
    """
    Check that the ORM metadata matches the reflected SQL database schema.
    """

    load_orm_models()

    orm_metadata = Base.metadata
    sql_metadata = MetaData()

    # Reflection loads the live database schema into SQLAlchemy objects so it can be compared with
    # the ORM metadata using the same table and column APIs.
    sql_metadata.reflect(env.db_engine)

    differences: list[SchemaDifference] = []

    for orm_table in orm_metadata.sorted_tables:
        sql_table = sql_metadata.tables.get(orm_table.name)
        differences.extend(check_table_sync(env, orm_table, sql_table))

    return differences


def check_table_sync(env: Env, orm_table: Table, sql_table: Table | None) -> list[SchemaDifference]:
    """
    Check that one ORM table matches its reflected SQL table.
    """

    log_verbose(env, f"Checking table {orm_table.name}")

    if sql_table is None:
        return [SchemaDifference(orm_table.name, None, "ORM table has no matching SQL table")]

    differences: list[SchemaDifference] = []
    orm_column_names = set(orm_table.columns.keys())
    sql_column_names = set(sql_table.columns.keys())

    for column_name in sorted(orm_column_names - sql_column_names):
        differences.append(SchemaDifference(orm_table.name, column_name, "ORM column has no matching SQL column"))

    for column_name in sorted(sql_column_names - orm_column_names):
        differences.append(SchemaDifference(orm_table.name, column_name, "SQL column has no matching ORM column"))

    for orm_column in orm_table.columns:
        if orm_column.name not in sql_column_names:
            continue

        sql_column = sql_table.columns[orm_column.name]
        differences.extend(check_column_sync(env, orm_table.name, orm_column, sql_column))

    return differences


def check_column_sync(
    env: Env,
    table_name: str,
    orm_column: Column[object],
    sql_column: Column[object],
) -> list[SchemaDifference]:
    """
    Check that one ORM column matches its reflected SQL column.
    """

    log_verbose(env, f"  Checking column {orm_column.name}")

    differences: list[SchemaDifference] = []

    orm_column_python_type = get_orm_python_type(orm_column.type)
    sql_column_python_type = get_sql_python_type(sql_column.type)
    if orm_column_python_type != sql_column_python_type:
        differences.append(SchemaDifference(
            table_name,
            orm_column.name,
            (
                "column type mismatch: "
                f"ORM {orm_column_python_type.__name__}, SQL {sql_column_python_type.__name__}"
            ),
        ))

    if orm_column.nullable != sql_column.nullable:
        differences.append(SchemaDifference(
            table_name,
            orm_column.name,
            f"nullable mismatch: ORM {orm_column.nullable}, SQL {sql_column.nullable}",
        ))

    if orm_column.primary_key != sql_column.primary_key:
        differences.append(SchemaDifference(
            table_name,
            orm_column.name,
            f"primary key mismatch: ORM {orm_column.primary_key}, SQL {sql_column.primary_key}",
        ))

    orm_auto_increment = is_orm_auto_increment(orm_column, len(orm_column.table.primary_key.columns))
    sql_auto_increment = sql_column.autoincrement is True
    if orm_auto_increment != sql_auto_increment:
        differences.append(SchemaDifference(
            table_name,
            orm_column.name,
            f"auto increment mismatch: ORM {orm_auto_increment}, SQL {sql_auto_increment}",
        ))

    if sql_column.server_default is not None:
        orm_default = get_orm_raw_default(env, orm_column.type, orm_column.default)
        default_difference = compare_orm_sql_raw_defaults(orm_default, sql_column.server_default)
        if default_difference is not None:
            differences.append(SchemaDifference(table_name, orm_column.name, default_difference))
    elif orm_column.default is not None:
        differences.append(SchemaDifference(
            table_name,
            orm_column.name,
            f"default mismatch: ORM {format_default(orm_column.default)}, SQL None",
        ))

    return differences


def load_orm_models():
    """
    Load all ORM model modules so their tables are registered in the ORM metadata.
    """

    for module_info in pkgutil.iter_modules(lib.db.models.__path__):
        importlib.import_module(f"{lib.db.models.__name__}.{module_info.name}")


def format_schema_differences(differences: list[SchemaDifference]) -> str:
    """
    Format schema differences grouped by table.
    """

    lines: list[str] = []
    current_table: str | None = None
    for difference in sorted(differences, key=lambda item: (item.table, item.column or '', item.message)):
        if difference.table != current_table:
            current_table = difference.table
            lines.append("")
            lines.append(difference.table)

        prefix = f"  {difference.column}: " if difference.column is not None else "  "
        lines.append(f"{prefix}{difference.message}")

    return "\n".join(lines)


def get_orm_raw_default(env: Env, orm_type: TypeEngine[object], orm_default: DefaultGenerator | None) -> object:
    """
    Get the default value of an ORM value processed by the raw SQL type of its column.
    """

    if orm_default is not None and not isinstance(orm_default, ColumnDefault):
        return orm_default

    orm_value = orm_default.arg if orm_default is not None else None

    # Type decorators can transform Python-side defaults before they are sent to SQL, so compare
    # defaults after applying the same bind processor that SQLAlchemy would use for inserts.
    bind_processor = orm_type.bind_processor(env.db_engine.dialect)
    if bind_processor is not None:
        return bind_processor(orm_value)

    return orm_value


def compare_orm_sql_raw_defaults(orm_default: object, sql_default: FetchedValue) -> str | None:
    """
    Compare the raw default value of an ORM column with that of an SQL column.
    """

    if not isinstance(sql_default, DefaultClause) or not isinstance(sql_default.arg, TextClause):
        return f"default mismatch: ORM {format_default(orm_default)}, SQL {format_default(sql_default)}"

    sql_text = sql_default.arg.text

    # MySQL may include ON UPDATE in the reflected default text, but that clause is separate from
    # the insert-time default modeled by Column.default.
    sql_update_match = re.match(r'(.+) ON UPDATE .+$', sql_text)
    if sql_update_match is not None:
        sql_text = sql_update_match.group(1)

    # Reflected SQL defaults are textual, so compare normalized special cases before falling back to
    # a plain string comparison.
    if sql_text == 'current_timestamp()':
        if isinstance(orm_default, FunctionType) and orm_default.__qualname__ == 'datetime.now':
            return None

        return f"default mismatch: ORM {format_default(orm_default)}, SQL {sql_text}"

    sql_string_match = re.match(r"'(.*)'$", sql_text)
    if sql_string_match is not None:
        sql_string = sql_string_match.group(1)
        if orm_default == sql_string:
            return None

        return f"default mismatch: ORM {format_default(orm_default)}, SQL {format_default(sql_string)}"

    if str(orm_default) == sql_text:
        return None

    return f"default mismatch: ORM {format_default(orm_default)}, SQL {sql_text}"


def get_orm_python_type(orm_type: TypeEngine[object]) -> type[object]:
    """
    Get the Python type of an ORM column.
    """

    if isinstance(orm_type, TypeDecorator):
        # Custom SQLAlchemy type decorators expose the application Python type through their wrapped
        # implementation rather than through the decorator itself.
        return cast(type[object], orm_type.impl.python_type)

    return orm_type.python_type


def get_sql_python_type(sql_type: TypeEngine[object]) -> type[object]:
    """
    Get the Python type of an SQL column.
    """

    if isinstance(sql_type, DOUBLE):
        return float

    return sql_type.python_type


def format_default(value: object) -> str:
    """
    Format a default value for human-readable output.
    """

    if isinstance(value, ColumnDefault):
        return repr(value.arg)

    return repr(value)


def is_orm_auto_increment(orm_column: Column[object], primary_key_column_count: int) -> bool:
    """
    Return whether an ORM column represents an auto-incrementing SQL column.
    """

    if orm_column.autoincrement is True:
        return True

    if orm_column.autoincrement is False:
        return False

    # SQLAlchemy's implicit auto-increment mode applies only to a single integer primary key.
    return (
        orm_column.autoincrement == 'auto'
        and orm_column.primary_key
        and primary_key_column_count == 1
        and get_orm_python_type(orm_column.type) is int
    )


if __name__ == '__main__':
    main()

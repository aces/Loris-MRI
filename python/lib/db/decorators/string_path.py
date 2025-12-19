from pathlib import Path

from sqlalchemy import String
from sqlalchemy.engine import Dialect
from sqlalchemy.types import TypeDecorator


class StringPath(TypeDecorator[Path]):
    """
    Decorator for a database path type.
    In SQL, the type will appear as a string.
    In Python, the type will appear as a path object.
    """

    impl = String
    cache_ok = True

    def process_bind_param(self, value: Path | None, dialect: Dialect) -> str | None:
        if value is None:
            return None

        return str(value)

    def process_result_value(self, value: str | None, dialect: Dialect) -> Path | None:
        if value is None:
            return None

        return Path(value)

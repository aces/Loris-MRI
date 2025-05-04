from datetime import datetime

from sqlalchemy import Integer
from sqlalchemy.engine import Dialect
from sqlalchemy.types import TypeDecorator


class IntDatetime(TypeDecorator[datetime]):
    """
    Decorator for a database timestamp integer type.
    In SQL, the type will appear as 'int'.
    In Python, the type will appear as a datetime object.
    """

    impl = Integer

    def process_bind_param(self, value: datetime | None, dialect: Dialect) -> int | None:
        if value is None:
            return None

        return int(value.timestamp())

    def process_result_value(self, value: int | None | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None

        return datetime.fromtimestamp(value)

from typing import Literal

from sqlalchemy import Integer
from sqlalchemy.engine import Dialect
from sqlalchemy.types import TypeDecorator


class IntBool(TypeDecorator[bool]):
    """
    Decorator for a database boolean integer type.
    In SQL, the type will appear as 'int'.
    In Python, the type will appear as a boolean.
    """

    impl = Integer

    def process_bind_param(self, value: bool | None, dialect: Dialect) -> Literal[0, 1] | None:
        match value:
            case True:
                return 1
            case False:
                return 0
            case None:
                return None

    def process_result_value(self, value: Literal[0, 1] | None, dialect: Dialect) -> bool | None:
        match value:
            case 1:
                return True
            case 0:
                return False
            case None:
                return None

from typing import Literal

from sqlalchemy import Enum
from sqlalchemy.engine import Dialect
from sqlalchemy.types import TypeDecorator


class TrueFalseBool(TypeDecorator[bool]):
    """
    Decorator for a database yes/no type.
    In SQL, the type will appear as 'true' | 'false'.
    In Python, the type will appear as a boolean.
    """

    impl = Enum('true', 'false')

    def process_bind_param(self, value: bool | None, dialect: Dialect) -> Literal['true', 'false'] | None:
        match value:
            case True:
                return 'true'
            case False:
                return 'false'
            case None:
                return None

    def process_result_value(self, value: Literal['true', 'false'] | None, dialect: Dialect) -> bool | None:
        match value:
            case 'true':
                return True
            case 'false':
                return False
            case None:
                return None

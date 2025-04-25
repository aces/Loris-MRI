from typing import Literal

from sqlalchemy import Enum
from sqlalchemy.engine import Dialect
from sqlalchemy.types import TypeDecorator


class YNBool(TypeDecorator[bool]):
    """
    Decorator for a database yes/no type.
    In SQL, the type will appear as 'Y' | 'N'.
    In Python, the type will appear as a boolean.
    """

    impl = Enum('Y', 'N')

    def process_bind_param(self, value: bool | None, dialect: Dialect) -> Literal['Y', 'N'] | None:
        match value:
            case True:
                return 'Y'
            case False:
                return 'N'
            case None:
                return None

    def process_result_value(self, value: Literal['Y', 'N'] | None, dialect: Dialect) -> bool | None:
        match value:
            case 'Y':
                return True
            case 'N':
                return False
            case None:
                return None

from typing import Annotated, TypeVar

from pydantic import BeforeValidator

T = TypeVar('T')


def validate_na(value: T) -> T | None:
    """
    Validate that a value is not N/A.
    """

    if value == 'n/a':
        return None

    return value


WithNA = Annotated[T | None, BeforeValidator(validate_na)]

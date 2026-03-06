from decimal import Decimal


def try_parse_decimal(string: str) -> Decimal | None:
    """
    Parse a string as a `Decimal` or return `None` if that string cannot be parsed.
    """

    try:
        return Decimal(string)
    except ValueError:
        return None


def try_parse_float(string: str) -> float | None:
    """
    Parse a string as a `float` or return `None` if that string cannot be parsed.
    """

    try:
        return float(string)
    except ValueError:
        return None


def try_parse_int(string: str) -> int | None:
    """
    Parse a string as an `int` or return `None` if that string cannot be parsed.
    """

    try:
        return int(string)
    except ValueError:
        return None

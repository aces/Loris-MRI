import math
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any

import numpy as np

JsonPrimitive = str | int | float | bool | None
JsonValue = JsonPrimitive | dict[str, 'JsonValue'] | list['JsonValue']


def jsonize(value: Any) -> JsonValue:
    """
    Recursively convert a value to a JSON-like value.
    """

    if value is None or isinstance(value, (str, int, bool)):
        return value

    # Handle float special cases
    if isinstance(value, float):
        if math.isinf(value) or math.isnan(value):
            return str(value)
        return value

    # Handle numpy types
    if isinstance(value, np.ndarray):
        if value.dtype.kind == 'f':  # type: ignore
            if np.any(np.isinf(value)) or np.any(np.isnan(value)):  # type: ignore
                return [
                    str(x)
                    if (isinstance(x, float) and (math.isinf(x) or math.isnan(x))) else jsonize(x)
                    for x in value.tolist()
                ]

        return value.tolist()

    if isinstance(value, np.integer):
        return int(value)  # type: ignore

    if isinstance(value, np.floating):
        if np.isinf(value) or np.isnan(value):  # type: ignore
            return str(value)  # type: ignore

        return float(value)  # type: ignore

    if isinstance(value, np.bool_):
        return bool(value)  # type: ignore

    # Handle datetime/dates
    if isinstance(value, (datetime, date)):
        return value.isoformat()

    # Handle Decimal
    if isinstance(value, Decimal):
        return float(value)

    # Handle UUID
    if isinstance(value, uuid.UUID):
        return str(value)

    # Handle iterables (list, tuple, set)
    if isinstance(value, (list, tuple, set)):
        return [jsonize(item) for item in value]  # type: ignore

    # Handle dictionaries
    if isinstance(value, dict):
        return {str(k): jsonize(v) for k, v in value.items()}  # type: ignore

    raise Exception(value)

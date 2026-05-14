from collections.abc import Callable
from pathlib import Path
from typing import Any

from bids import BIDSLayout
from bids.layout import BIDSFile
from loris_utils.iter import find


def try_get_pybids_value(layout: BIDSLayout, **args: Any) -> Any | None:
    """
    Get zero or one PyBIDS value using the provided arguments, or raise an exception if multiple
    values are found.
    """

    match layout.get(**args):  # type: ignore
        case []:
            return None
        case [value]:  # type: ignore
            return value  # type: ignore
        case values:  # type: ignore
            raise Exception(f"Expected one or zero PyBIDS value but found {len(values)}.")  # type: ignore


def get_pybids_file_path(file: BIDSFile) -> Path:
    """
    Get the path of a PyBIDS file.
    """

    # The PyBIDS file class does not use the standard path object nor supports type checking.
    return Path(file.path)  # type: ignore


def find_pybids_file_path(files: list[BIDSFile], predicate: Callable[[BIDSFile], bool]) -> Path | None:
    """
    Find the path of a file in a list of PyBIDS files using a predicate, or return `None` if no
    file matches the predicate.
    """

    file = find(files, predicate)
    return get_pybids_file_path(file) if file is not None else None

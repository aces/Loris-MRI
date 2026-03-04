from collections.abc import Callable
from pathlib import Path

from bids.layout import BIDSFile
from loris_utils.iter import find


def get_bids_file_path(file: BIDSFile) -> Path:
    """
    Get the path of a PyBIDS file.
    """

    # The PyBIDS file class does not use the standard path object nor supports type checking.
    return Path(file.path)  # type: ignore


def find_bids_file_path(files: list[BIDSFile], predicate: Callable[[BIDSFile], bool]) -> Path | None:
    """
    Find the path of a file in a list of PyBIDS files using a predicate, or return `None` if no
    file matches the predicate.
    """

    file = find(files, predicate)
    return get_bids_file_path(file) if file is not None else None

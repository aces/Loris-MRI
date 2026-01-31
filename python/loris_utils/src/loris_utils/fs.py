import os
import re
import tarfile
import tempfile
from collections.abc import Iterator
from datetime import datetime
from pathlib import Path


def extract_archive(tar_path: str, prefix: str, dir_path: str) -> str:
    """
    Extract an archive in a new temporary directory inside the given directory and return
    the new directory location.
    """

    date_string = datetime.now().strftime('%Y-%m-%d_%Hh%Mm%Ss')
    full_prefix = f'{prefix}_DIR_{date_string}_'
    extract_path = tempfile.mkdtemp(prefix=full_prefix, dir=dir_path)
    with tarfile.open(tar_path) as tar_file:
        tar_file.extractall(extract_path)

    return extract_path


def iter_all_dir_files(dir_path: Path) -> Iterator[Path]:
    """
    Iterate through all the files in a directory recursively, and yield the path of each file
    relative to that directory.
    """

    for item_path in dir_path.iterdir():
        if item_path.is_dir():
            yield from iter_all_dir_files(item_path)
        elif item_path.is_file():
            yield item_path.relative_to(dir_path)


def is_directory_empty(dir_path: str) -> bool:
    """
    Check whether a directory is empty or not.
    """

    with os.scandir(dir_path) as dir_iterator:
        return next(dir_iterator, None) is None


def remove_empty_directories(dir_path: str):
    """
    Recursively remove all the empty directories in a directory, including itself if needed.
    """

    for subdir_path, _, _ in os.walk(dir_path, topdown=False):
        if is_directory_empty(subdir_path):
            os.rmdir(subdir_path)


def search_dir_file_with_regex(dir_path: Path, regex: str) -> Path | None:
    """
    Search for a file or directory within a directory whose name matches a regular expression, or
    return `None` if no such file is found.
    """

    for file_path in dir_path.iterdir():
        if re.search(regex, file_path.name):
            return file_path

    return None

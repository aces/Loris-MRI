import os
import re
import shutil
import tarfile
import tempfile
from collections.abc import Iterator
from datetime import datetime
from pathlib import Path

import lib.exitcode
from lib.env import Env
from lib.logging import log_error_exit, log_verbose, log_warning


def extract_archive(env: Env, tar_path: str, prefix: str, dir_path: str) -> str:
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


def iter_all_dir_files(dir_path: str) -> Iterator[str]:
    """
    Iterate through all the files in a directory recursively, and yield the path of each file
    relative to that directory.
    """

    for sub_dir_path, _, file_names in os.walk(dir_path):
        for file_name in file_names:
            file_path = os.path.join(sub_dir_path, file_name)
            yield os.path.relpath(file_path, start=dir_path)


def remove_directory(env: Env, path: str):
    """
    Delete a directory and its content.
    """

    if os.path.exists(path):
        try:
            shutil.rmtree(path)
        except PermissionError as error:
            log_warning(env, f"Could not delete {path}. Error was: {error}")


def copy_file(env: Env, old_path: str, new_path: str):
    """
    Copy a file on the file system.
    """

    log_verbose(env, f"Moving {old_path} to {new_path}")
    shutil.copytree(old_path, new_path, dirs_exist_ok=True)
    if not os.path.exists(new_path):
        log_error_exit(env, f"Could not copy {old_path} to {new_path}", lib.exitcode.COPY_FAILURE)


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


def get_file_extension(file_name: str) -> str:
    """
    Get the extension (including multiple extensions) of a file name or path without the leading
    dot.
    """

    parts = file_name.split('.', maxsplit=1)
    if len(parts) == 1:
        return ''

    return parts[1]


def replace_file_extension(file_name: str, extension: str) -> str:
    """
    Replace the extension (including multiple extensions) of a file name or path by another
    extension.
    """

    parts = file_name.split('.')
    return f'{parts[0]}.{extension}'


def search_dir_file_with_regex(dir_path: Path, regex: str) -> Path | None:
    """
    Search for a file or directory within a directory whose name matches a regular expression, or
    return `None` if no such file is found.
    """

    for file_path in dir_path.iterdir():
        if re.search(regex, file_path.name):
            return file_path

    return None

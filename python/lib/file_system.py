import os
import shutil
import tarfile
import tempfile
from datetime import datetime

import lib.exitcode
from lib.env import Env
from lib.logging import log_error_exit, log_verbose, log_warning


def extract_archive(env: Env, tar_path: str, prefix: str, dir_path: str):
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

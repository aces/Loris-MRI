import os
from collections.abc import Generator


def iter_all_files(dir_path: str) -> Generator[str, None, None]:
    """
    Iterate through all the files in a directory recursively, and yield the path of each file
    relative to that directory.
    """

    for sub_dir_path, _, file_names in os.walk(dir_path):
        for file_name in file_names:
            file_path = os.path.join(sub_dir_path, file_name)
            yield os.path.relpath(file_path, start=dir_path)

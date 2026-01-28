import re

from lib.db.queries.imaging_file_type import get_all_imaging_file_types
from lib.env import Env


# FIXME: This code seems to be MRI-specific code that makes assumptions that are not true for MEG.
# Create good abstractions for both MRI and MEG.
def determine_imaging_file_type(env: Env, file_name: str) -> str | None:
    """
    Determine the file type of an imaging file from the database using its name, or return `None`
    if no corresponding file type is found.
    """

    imaging_file_types = get_all_imaging_file_types(env.db)

    for imaging_file_type in imaging_file_types:
        regex = re.escape(imaging_file_type.type) + r'(\.gz)?$'
        if re.search(regex, file_name):
            return imaging_file_type.type

    return None


def get_check_imaging_file_type(env: Env, file_name: str) -> str:
    """
    Get the file type of an imaging file or raise an exception if that file type is not
    registered in the database.
    """

    file_type = determine_imaging_file_type(env, file_name)
    if file_type is None:
        raise Exception("No matching file type found in the database.")

    return file_type

import re

from lib.db.queries.imaging_file_type import get_all_imaging_file_types
from lib.env import Env


def determine_bids_file_type(env: Env, file_name: str) -> str | None:
    """
    Determine the file type of a BIDS file from the database using its name, or return `None` if no
    corresponding file type is found.
    """

    imaging_file_types = get_all_imaging_file_types(env.db)

    for imaging_file_type in imaging_file_types:
        regex = re.escape(imaging_file_type.type) + r'(\.gz)?$'
        if re.search(regex, file_name):
            return imaging_file_type.type

    return None

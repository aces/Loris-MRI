from pathlib import Path

from loris_utils.path import get_path_extension

from lib.db.models.imaging_file_type import DbImagingFileType
from lib.db.queries.imaging_file_type import try_get_imaging_file_type_with_name
from lib.env import Env


def get_check_bids_imaging_file_type_from_extension(env: Env, file_path: Path) -> DbImagingFileType:
    """
    Get an imaging file type from a file name, or raise an exception if that file name is incorrect
    or if the file type is not present in the database.
    """

    file_extension = get_path_extension(file_path)
    if file_extension is None:
        raise Exception(f"Cannot get imaging file type of file with no extension '{file_path}'.")

    file_type_name = file_extension.removesuffix('.gz')
    return get_check_bids_imaging_file_type(env, file_type_name)


def get_check_bids_imaging_file_type(env: Env, file_type_name: str) -> DbImagingFileType:
    """
    Get an imaging file type from a file type name, or raise an exception if that file type is not
    present in the database.
    """

    file_type = try_get_imaging_file_type_with_name(env.db, file_type_name)
    if file_type is None:
        raise Exception(f"Imaging file type not found for file type '{file_type_name}'.")

    return file_type

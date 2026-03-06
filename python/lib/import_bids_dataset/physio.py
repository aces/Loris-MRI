from pathlib import Path

from loris_utils.crypto import compute_file_blake2b_hash

from lib.db.models.physio_modality import DbPhysioModality
from lib.db.models.physio_output_type import DbPhysioOutputType
from lib.db.queries.physio import try_get_physio_modality_with_name, try_get_physio_output_type_with_name
from lib.db.queries.physio_file import try_get_physio_file_with_hash
from lib.env import Env


def get_check_bids_physio_modality(env: Env, data_type_name: str) -> DbPhysioModality:
    """
    Get the physiological modality of a BIDS acquisition, or raise an exception if it is not
    present in the database.
    """

    modality = try_get_physio_modality_with_name(env.db, data_type_name)
    if modality is None:
        raise Exception(f"Modality not found for BIDS data type '{data_type_name}'.")

    return modality


def get_check_bids_physio_output_type(env: Env, type: str) -> DbPhysioOutputType:
    """
    Get the physiological output type of a BIDS acquisition, or raise an exception if it is not
    present in the database.
    """

    output_type = try_get_physio_output_type_with_name(env.db, type)
    if output_type is None:
        raise Exception(f"Output type not found for output '{type}'.")

    return output_type


def get_check_bids_physio_file_hash(env: Env, file_path: Path) -> str:
    """
    Compute the BLAKE2b hash of a physiological file and raise an exception if that hash is already
    registered in the database.
    """

    file_hash = compute_file_blake2b_hash(file_path)

    file = try_get_physio_file_with_hash(env.db, file_hash)
    if file is not None:
        raise Exception(f"Physiological file with hash '{file_hash}' is already present in the database.")

    return file_hash

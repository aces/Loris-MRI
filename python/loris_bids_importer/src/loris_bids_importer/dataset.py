import re
from datetime import datetime
from pathlib import Path

from lib.config import get_data_dir_path_config
from lib.db.models.bids_dataset import DbBidsDataset
from lib.db.models.bids_file import DbBidsFile
from lib.db.queries.bids_dataset import try_get_bids_dataset_with_path
from lib.db.queries.bids_file import try_get_bids_file_with_dataset_id_path
from lib.env import Env
from lib.logging import log_error_exit
from loris_bids_utils.reader import BidsDatasetReader
from loris_utils.crypto import compute_file_blake2b_hash

from loris_bids_importer.importer import BidsImporter, BidsImporterArgs


def make_bids_importer(env: Env, args: BidsImporterArgs, bids: BidsDatasetReader) -> BidsImporter:
    """
    Make the LORIS BIDS importer object from the BIDS import input information.
    """

    data_dir_path = get_data_dir_path_config(env)

    if args.copy:
        loris_bids_path = get_copy_dataset_path(env, bids, data_dir_path)
    else:
        loris_bids_path = get_no_copy_dataset_path(env, bids, data_dir_path)

    loris_bids_dataset = get_or_create_loris_bids_dataset(env, loris_bids_path)

    return BidsImporter(
        args               = args,
        data_dir_path      = data_dir_path,
        loris_bids_dataset = loris_bids_dataset
    )


def get_copy_dataset_path(env: Env, bids: BidsDatasetReader, data_dir_path: Path) -> Path:
    """
    Get the LORIS BIDS dataset path relative to the LORIS data directory in the copy mode, creating
    it if it does not exist yet.
    """

    try:
        dataset_description = bids.dataset_description_file
    except Exception as error:
        log_error_exit(env, str(error))

    if dataset_description is None:
        log_error_exit(
            env,
            "No file 'dataset_description.json' found in the input BIDS dataset.",
        )

    # Sanitize the dataset metadata to have a usable name for the directory.
    dataset_name    = re.sub(r'[^0-9a-zA-Z]+',   '_', dataset_description.data['Name'])
    dataset_version = re.sub(r'[^0-9a-zA-Z\.]+', '_', dataset_description.data['BIDSVersion'])

    loris_bids_path = Path('bids_imports') / f'{dataset_name}_BIDSVersion_{dataset_version}'

    # Create the BIDS dataset directory if it does not exist yet.
    (data_dir_path / loris_bids_path).mkdir(exist_ok=True)

    return loris_bids_path


def get_no_copy_dataset_path(env: Env, bids: BidsDatasetReader, data_dir_path: Path) -> Path:
    """
    Get the LORIS BIDS dataset path relative to the LORIS data directory in the no-copy mode.
    """

    if not bids.path.is_relative_to(data_dir_path):
        log_error_exit(
            env,
            "The source BIDS dataset should be inside the LORIS data directory in no-copy mode.",
        )

    return bids.path.relative_to(data_dir_path)


def get_or_create_loris_bids_dataset(env: Env, bids_path: Path) -> DbBidsDataset:
    """
    Get a BIDS dataset from the database using its LORIS data-directory-relative path,
    or create it if it does not already exist.
    """

    bids_dataset = try_get_bids_dataset_with_path(env.db, bids_path)
    if bids_dataset is not None:
        bids_dataset.update_time = datetime.now()
        env.db.flush()
        return bids_dataset

    bids_dataset = DbBidsDataset(
        path = bids_path
    )

    env.db.add(bids_dataset)
    env.db.flush()

    return bids_dataset


def get_or_create_loris_bids_file(
    env: Env,
    importer: BidsImporter,
    source_file_path: Path,
    loris_file_path: Path,
) -> DbBidsFile:
    """
    Create or update the LORIS database record for a BIDS file.
    """

    # The LORIS file path is relative to the LORIS data directory, it needs to be made relative to
    # its LORIS BIDS dataset instead.
    bids_file_path = loris_file_path.relative_to(importer.loris_bids_dataset.path)

    source_bids_file_path = source_file_path.relative_to(importer.args.source_bids_path)

    derivative = (
        importer.args.type == 'derivative'
        or source_bids_file_path.parts[0] == 'derivatives'
    )

    blake2b_hash = compute_file_blake2b_hash(importer.data_dir_path / loris_file_path)

    bids_file = try_get_bids_file_with_dataset_id_path(env.db, importer.loris_bids_dataset.id, bids_file_path)

    if bids_file is None:
        bids_file = DbBidsFile(
            dataset_id    = importer.loris_bids_dataset.id,
            path          = bids_file_path,
            source_path   = source_bids_file_path,
            blake2b_hash  = blake2b_hash,
            derivative    = derivative,
        )

        env.db.add(bids_file)
    else:
        bids_file.source_path = source_bids_file_path
        bids_file.blake2b_hash = blake2b_hash

    env.db.flush()

    return bids_file

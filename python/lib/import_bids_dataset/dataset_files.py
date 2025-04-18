import os

from bids import BIDSLayout

import lib.utilities
from lib.env import Env
from lib.import_bids_dataset.participant import BidsParticipant, write_bids_participants_file


def add_dataset_files(env: Env, source_bids_dir_path: str, loris_bids_dir_path: str, verbose: bool):
    """
    Add the non-acquisition files of a LORIS BIDS directory, based on the content of this directory
    and the source directory it is imported from.
    """

    copy_static_dataset_files(source_bids_dir_path, loris_bids_dir_path, verbose)

    generate_participants_file(env, loris_bids_dir_path)


def copy_static_dataset_files(source_bids_dir_path: str, loris_bids_dir_path: str, verbose: bool):
    """
    Copy the static files of the source BIDS dataset to te LORIS BIDS dataset.
    """

    for file_name in ['README', 'dataset_description.json']:
        source_file_path = os.path.join(source_bids_dir_path, file_name)
        if not os.path.isfile(source_file_path):
            continue

        loris_file_path = os.path.join(loris_bids_dir_path, file_name)

        lib.utilities.copy_file(source_file_path, loris_file_path, verbose)  # type: ignore


def generate_participants_file(env: Env, bids_dir_path: str):
    """
    Generate the `participants.tsv` file of a BIDS dataset using the information present in the
    directory and the LORIS database.
    """

    bids_layout = BIDSLayout(bids_dir_path)
    bids_subjects: list[str] = bids_layout.get_subjects()  # type: ignore
    bids_participants = list(map(BidsParticipant, bids_subjects))
    write_bids_participants_file(bids_participants, bids_dir_path)

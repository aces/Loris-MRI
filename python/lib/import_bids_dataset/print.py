from loris_bids_reader.reader import BidsDatasetReader

from lib.env import Env
from lib.import_bids_dataset.env import BidsImportEnv
from lib.logging import log


def print_bids_info(env: Env, bids: BidsDatasetReader):
    """
    Print information about the BIDS dataset to import.
    """

    log(env, f"Found {len(bids.data_types)} data types:")
    for data_type in bids.data_types:
        log(env, f"- {data_type.name}")

    log(env, f"Found {len(bids.subject_labels)} subjects:")
    for subject_label in bids.subject_labels:
        log(env, f"- {subject_label}")

    log(env, f"Found {len(bids.session_labels)} sessions:")
    for session_label in bids.session_labels:
        log(env, f"- {session_label}")


def print_bids_import_summary(env: Env, import_env: BidsImportEnv):
    """
    Print a summary of this BIDS import process.
    """

    log(
        env,
        (
            f"Processed {import_env.processed_acquisitions_count} acquisitions, including"
            f" {import_env.imported_acquisitions_count} imports, {import_env.ignored_acquisitions_count} ignores, and"
            f" {import_env.failed_acquisitions_count} errors."
        ),
    )

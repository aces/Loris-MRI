from lib.env import Env
from lib.logging import log
from loris_bids_utils.reader import BidsDatasetReader

from loris_bids_importer.importer import BidsImporter


def print_bids_info(env: Env, bids: BidsDatasetReader):
    """
    Print information about the BIDS dataset to import.
    """

    log(env, f"Found {len(bids.subject_labels)} subjects:")
    for subject_label in bids.subject_labels:
        log(env, f"- {subject_label}")

    log(env, f"Found {len(bids.session_labels)} sessions:")
    for session_label in bids.session_labels:
        log(env, f"- {session_label}")

    log(env, f"Found {len(bids.data_type_names)} data types:")
    for data_type_name in bids.data_type_names:
        log(env, f"- {data_type_name}")


def print_bids_import_summary(env: Env, importer: BidsImporter):
    """
    Print a summary of this BIDS import process.
    """

    log(
        env,
        (
            f"Processed {importer.processed_acquisitions_count} acquisitions, including"
            f" {importer.imported_acquisitions_count} imports, {importer.ignored_acquisitions_count} ignores, and"
            f" {importer.failed_acquisitions_count} errors."
        ),
    )

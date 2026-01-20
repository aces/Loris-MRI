
import os

from loris_bids_reader.files.scans import BidsScansTsvFile

import lib.utilities


def copy_scans_tsv_file_to_loris_bids_dir(
    scans_file: BidsScansTsvFile,
    bids_sub_id: str,
    loris_bids_root_dir: str,
    data_dir: str,
) -> str:
    """
    Copy the scans.tsv file to the LORIS BIDS directory for the subject.
    """

    original_file_path = scans_file.path
    final_file_path = os.path.join(loris_bids_root_dir, f'sub-{bids_sub_id}', scans_file.path.name)

    # copy the scans.tsv file to the new directory
    if os.path.exists(final_file_path):
        lib.utilities.append_to_tsv_file(original_file_path, final_file_path, 'filename', False)  # type: ignore
    else:
        lib.utilities.copy_file(original_file_path, final_file_path, False)  # type: ignore

    # determine the relative path and return it
    return os.path.relpath(final_file_path, data_dir)

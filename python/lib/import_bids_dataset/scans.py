from typing import Any

from loris_bids_reader.files.scans import BidsScansTsvFile, BidsScanTsvRow
from loris_utils.crypto import compute_file_blake2b_hash


def add_bids_scans_file_parameters(
    scans_file: BidsScansTsvFile,
    scan_row: BidsScanTsvRow,
    file_parameters: dict[str, Any],
):
    """
    Read a BIDS `scans.tsv` file and row, and add its information to the LORIS file parameters
    dictionary.
    """

    file_parameters['scan_acquisition_time']    = scan_row.get_acquisition_time()
    file_parameters['age_at_scan']              = scan_row.get_age_at_scan()
    file_parameters['scans_tsv_file']           = scans_file.path
    file_parameters['scans_tsv_file_bake2hash'] = compute_file_blake2b_hash(scans_file.path)

from typing import Any

from lib.db.models.session import DbSession
from loris_bids_utils.files.scans import BidsScansTsvFile, BidsScanTsvRow
from loris_utils.crypto import compute_file_blake2b_hash

from loris_bids_importer.copy_files import get_loris_scans_path
from loris_bids_importer.importer import BidsImporter


def add_bids_scans_file_parameters(
    importer: BidsImporter,
    session: DbSession,
    scans_file: BidsScansTsvFile,
    scan_row: BidsScanTsvRow,
    file_parameters: dict[str, Any],
):
    """
    Read a BIDS `scans.tsv` file and row, and add its information to the LORIS file parameters
    dictionary.
    """

    file_parameters['scan_acquisition_time']     = scan_row.get_acquisition_time()
    file_parameters['age_at_scan']               = scan_row.get_age_at_scan()
    file_parameters['scans_tsv_file']            = get_loris_scans_path(importer, scans_file, session)
    file_parameters['scans_tsv_file_blake2hash'] = compute_file_blake2b_hash(scans_file.path)

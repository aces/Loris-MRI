from pathlib import Path
from typing import Any

from lib.util.crypto import compute_file_blake2b_hash
from loris_bids_reader.scans import BIDSScanRow


def add_scan_tsv_file_parameters(scan_tsv: BIDSScanRow, scans_tsv_path: Path, file_parameters: dict[str, Any]):
    """
    Add a scans.tsv file and row parameters to a LORIS file parameters dictionary.
    """

    file_parameters['scan_acquisition_time']    = scan_tsv.acq_time
    file_parameters['age_at_scan']              = scan_tsv.age_at_scan
    file_parameters['scans_tsv_file']           = scans_tsv_path
    file_parameters['scans_tsv_file_bake2hash'] = compute_file_blake2b_hash(scans_tsv_path)

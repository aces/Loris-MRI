import csv
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from dateutil.parser import ParserError, parse

from lib.util.crypto import compute_file_blake2b_hash


@dataclass
class BidsTsvScan:
    """
    Information about a scan found in a row of a `scans.tsv` file of a BIDS dataset.
    """

    file_name        : str
    acquisition_time : datetime | None
    age_at_scan      : str | None


def read_bids_scans_tsv_file(scans_tsv_path: Path) -> dict[str, BidsTsvScan]:
    """
    Read a `scans.tsv` file of a BIDS dataset and get the scan rows indexed by file name. Raise an
    exception if the `scans.tsv` file is incorrect.
    """

    tsv_scans: dict[str, BidsTsvScan] = {}
    with open(scans_tsv_path) as scans_tsv_file:
        reader = csv.DictReader(scans_tsv_file.readlines(), delimiter='\t')
        if reader.fieldnames is None or 'filename' not in reader.fieldnames:
            raise Exception(f"Missing 'filename' field in scans.tsv file '{scans_tsv_path}'.")

        for tsv_scan_row in reader:
            tsv_row = read_bids_scans_tsv_row(tsv_scan_row, scans_tsv_path)
            tsv_scans[tsv_row.file_name] = tsv_row

    return tsv_scans


def read_bids_scans_tsv_row(tsv_scan_row: dict[str, str], scans_tsv_path: Path) -> BidsTsvScan:
    """
    Read a `scans.tsv` row, or raise an exception if that row is incorrect.
    """

    file_name = tsv_scan_row.get('filename')
    if file_name is None:
        raise Exception(f"Missing 'filename' value in scans.tsv file '{scans_tsv_path}'.")

    acquisition_time = _read_acquisition_time(tsv_scan_row)
    age_at_scan      = _read_age_at_scan(tsv_scan_row)

    return BidsTsvScan(
        file_name        = file_name,
        acquisition_time = acquisition_time,
        age_at_scan      = age_at_scan,
    )


def write_bids_scans_tsv_file(tsv_scans: dict[str, BidsTsvScan], scans_tsv_path: Path):
    """
    Write the `scans.tsv` file from a set of scan rows.
    """

    with open(scans_tsv_path, 'w') as scans_tsv_file:
        writer = csv.writer(scans_tsv_file, delimiter='\t')
        writer.writerow(['filename', 'acq_time', 'age_at_scan'])

        for tsv_scan in sorted(tsv_scans.values(), key=lambda tsv_scan: tsv_scan.file_name):
            writer.writerow([
                tsv_scan.file_name,
                tsv_scan.acquisition_time,
                tsv_scan.age_at_scan
            ])


def merge_bids_tsv_scans(tsv_scans: dict[str, BidsTsvScan], new_tsv_scans: dict[str, BidsTsvScan]):
    """
    Copy a set of scans.tsv rows into another one. The rows of the first set are replaced by those
    of these second if there are duplicates.
    """

    for new_tsv_scan in new_tsv_scans.values():
        tsv_scans[new_tsv_scan.file_name] = new_tsv_scan


def _read_acquisition_time(tsv_scan_row: dict[str, str]) -> datetime | None:
    """
    Read the acquisition time field of a scan from a `scans.tsv` row.
    """

    for field_name in ['acq_time', 'mri_acq_time', 'eeg_acq_time']:
        acquisition_time = tsv_scan_row.get(field_name)
        if acquisition_time is None or acquisition_time == 'n/a':
            continue

        try:
            return parse(acquisition_time)
        except ParserError:
            pass

    return None


def _read_age_at_scan(tsv_scan_row: dict[str, str]) -> str | None:
    """
    Read the age at scan field of a scan from a `scans.tsv` row.
    """

    for field_name in ['age', 'age_at_scan', 'age_acq_time']:
        age_at_scan = tsv_scan_row.get(field_name)
        if age_at_scan is not None:
            return age_at_scan.strip()

    return None


def add_scan_tsv_file_parameters(scan_tsv: BidsTsvScan, scans_tsv_path: Path, file_parameters: dict[str, Any]):
    """
    Add a scans.tsv file and row parameters to a LORIS file parameters dictionary.
    """

    file_parameters['scan_acquisition_time']    = scan_tsv.acquisition_time
    file_parameters['age_at_scan']              = scan_tsv.age_at_scan
    file_parameters['scans_tsv_file']           = scans_tsv_path
    file_parameters['scans_tsv_file_bake2hash'] = compute_file_blake2b_hash(scans_tsv_path)

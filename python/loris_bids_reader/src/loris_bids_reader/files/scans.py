from datetime import datetime
from pathlib import Path

import dateutil.parser
from loris_utils.iter import find, replace_or_append

from loris_bids_reader.tsv import BidsTsvFile, BidsTsvRow


class BidsScanTsvRow(BidsTsvRow):
    """
    Class representing a BIDS scans.tsv row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#scans-file
    """

    def get_acquisition_time(self) -> datetime | None:
        """
        Get the acquisition time of the acquisition file.
        """

        acq_time_string = self.data.get('acq_time')
        if acq_time_string is not None:
            if acq_time_string == 'n/a':
                return None

            try:
                acq_time = dateutil.parser.parse(acq_time_string)
            except ValueError as e:
                raise Exception(f"Could not convert acquisition time {acq_time_string}' to datetime: {e}")
            return acq_time

        return None

    def get_age_at_scan(self) -> str | None:
        """
        Get the age at the time of acquisition.
        """

        # list of possible header names containing the age information
        age_header_list = ['age', 'age_at_scan', 'age_acq_time']

        for header_name in age_header_list:
            age_string = self.data.get(header_name)
            if age_string is not None:
                return age_string.strip()

        return None


class BidsScansTsvFile(BidsTsvFile[BidsScanTsvRow]):
    """
    Class representing a BIDS scans.tsv file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#scans-file
    """

    def __init__(self, path: Path):
        super().__init__(BidsScanTsvRow, path)

    def get_row(self, file_path: Path) -> BidsScanTsvRow | None:
        """
        Get the row corresponding to the given file path.
        """

        return find(self.rows, lambda row: file_path.name == row.data['filename'])

    def set_row(self, scan: BidsScanTsvRow):
        """
        Add a row in the `scans.tsv` file, replacing it if a row already exists for its file name.
        """

        replace_or_append(self.rows, scan, lambda row: row.data['filename'] == scan.data['filename'])

    def merge(self, other: 'BidsScansTsvFile'):
        """
        Copy another `scans.tsv` file into this file. The rows of this file are replaced by those
        of the other file if there are duplicates.
        """

        for other_row in other.rows:
            self.set_row(other_row)

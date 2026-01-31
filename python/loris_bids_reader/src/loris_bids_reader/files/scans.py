from datetime import datetime
from pathlib import Path

import dateutil.parser
from loris_utils.iter import find

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

        if 'acq_time' in self.data:
            # the variable name could be mri_acq_time, but is eeg originally.
            eeg_acq_time = self.data['acq_time']

            if eeg_acq_time == 'n/a':
                return None

            try:
                eeg_acq_time = dateutil.parser.parse(eeg_acq_time)
            except ValueError as e:
                raise Exception(f"Could not convert acquisition time {eeg_acq_time}' to datetime: {e}")
            return eeg_acq_time

        return None

    def get_age_at_scan(self) -> str | None:
        """
        Get the age at the time of acquisition.
        """

        # list of possible header names containing the age information
        age_header_list = ['age', 'age_at_scan', 'age_acq_time']

        for header_name in age_header_list:
            if header_name in self.data:
                return self.data[header_name].strip()

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

        return find(self.rows, lambda row: file_path.name in row.data['filename'])

from datetime import datetime
from pathlib import Path

import dateutil.parser
from loris_utils.iter import find, replace_or_append

from loris_bids_utils.tsv import BidsTsvFile, BidsTsvRow


class BidsScanTsvRow(BidsTsvRow):
    """
    Class representing a BIDS scans.tsv row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#scans-file
    """

    file_path: Path
    """
    The path of the scan file relative to the scans.tsv file.
    """

    def __init__(self, data: dict[str, str | None]):
        super().__init__(data)
        file_path = self.data.get('filename')
        if file_path is None:
            raise Exception("Missing filename field in `scans.tsv` file.")

        self.file_path = Path(file_path)

    def set_file_name(self, file_name: str):
        """
        Set the name of the scan file of this row.
        """

        self.file_path        = self.file_path.with_name(file_name)
        self.data['filename'] = str(self.file_path)

    def get_acquisition_time(self) -> datetime | None:
        """
        Get the acquisition time of the acquisition file.
        """

        acq_time_string = self.data.get('acq_time')
        if acq_time_string is not None:
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

        # According to the specification, the 'filename' column is the path of the acquisition file
        # relative to the directory in which the scans.tsv file is located.
        relative_path = file_path.relative_to(self.path.parent)
        return find(self.rows, lambda row: relative_path == row.file_path)

    def set_row(self, scan: BidsScanTsvRow):
        """
        Add a row in the `scans.tsv` file, replacing it if a row already exists for its file name.
        """

        replace_or_append(self.rows, scan, lambda row: row.file_path == scan.file_path)

    def merge(self, other: 'BidsScansTsvFile'):
        """
        Copy another `scans.tsv` file into this file. The rows of this file are replaced by those
        of the other file if there are duplicates.
        """

        for other_row in other.rows:
            self.set_row(other_row)

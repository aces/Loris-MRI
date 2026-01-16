import csv
from pathlib import Path
from typing import Any


class BidsTsvFile:
    """
    Class for a BIDS TSV file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/common-principles.html#tabular-files
    """

    path: Path
    rows: list[dict[str, Any]]

    def __init__(self, path: Path):
        self.path = path
        self.rows = []

        with open(self.path) as file:
            reader = csv.DictReader(file, delimiter='\t')
            for row in reader:
                self.rows.append(row)

import csv
from pathlib import Path
from typing import Any, Generic, TypeVar


class BidsTsvRow:
    """
    Class for a BIDS TSV row.
    Documentation: https://bids-specification.readthedocs.io/en/stable/common-principles.html#tabular-files
    """

    data: dict[str, Any]

    def __init__(self, data: dict[str, Any]):
        self.data = data


T = TypeVar('T', bound='BidsTsvRow')


class BidsTsvFile(Generic[T]):
    """
    Class for a BIDS TSV file.
    Documentation: https://bids-specification.readthedocs.io/en/stable/common-principles.html#tabular-files
    """

    path: Path
    rows: list[T]

    def __init__(self, model: type[T], path: Path):
        self.path = path
        self.rows = []

        with open(self.path, encoding='utf-8-sig') as file:
            reader = csv.DictReader(file, delimiter='\t')
            for row in reader:
                self.rows.append(model(row))

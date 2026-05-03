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

    def get_field_names(self) -> list[str]:
        """
        Get the names of the fields of this file.
        """

        fields: list[str] = []
        for row in self.rows:
            for field in row.data.keys():
                if field not in fields:
                    fields.append(field)

        return fields

    def write(self, path: Path):
        """
        Write the TSV file to a file at the given path, creating it if necessary.
        """

        fields = self.get_field_names()

        with open(path, 'w', newline='') as file:
            writer = csv.DictWriter(file, fieldnames=fields, delimiter='\t')
            writer.writeheader()

            for row in self.rows:
                writer.writerow(row.data)

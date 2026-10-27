import csv
from pathlib import Path
from typing import Generic, TypeVar


class BidsTsvRow:
    """
    Class for a BIDS TSV row.
    Documentation: https://bids-specification.readthedocs.io/en/stable/common-principles.html#tabular-files
    """

    data: dict[str, str | None]

    def __init__(self, data: dict[str, str | None]):
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

        # The 'utf-8-sig' encoding is used to support some datasets where metadata files may contain
        # a byte-order mark (BOM).
        with open(self.path, encoding='utf-8-sig') as file:
            reader = csv.DictReader(file, delimiter='\t')
            for row in reader:
                # Skip empty lines (such as trailing newlines).
                if row == {}:
                    continue

                row_data = {
                    key: normalize_bids_tsv_value(value)
                    for key, value in row.items()
                }

                self.rows.append(model(row_data))

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

    def write(self, path: Path | None = None):
        """
        Write the TSV file at the given path. If the path is not provided, the path of this file is
        used, overwriting existing data.
        """

        path = path if path is not None else self.path

        fields = self.get_field_names()

        with open(path, 'w', newline='') as file:
            writer = csv.DictWriter(file, fieldnames=fields, delimiter='\t')
            writer.writeheader()

            for row in self.rows:
                writer.writerow(row.data)


def normalize_bids_tsv_value(value: str | None) -> str | None:
    """
    Normalize a BIDS TSV value, converting it to `None` if it is empty or `n/a` (case-insensitive).
    """

    if value is None or value == '' or value.lower() == 'n/a':
        return None

    return value

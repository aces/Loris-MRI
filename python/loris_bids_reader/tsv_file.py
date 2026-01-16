import csv
from pathlib import Path
from typing import Generic, TypeVar

from pydantic import BaseModel

from lib.util.path import replace_path_extension
from loris_bids_reader.data_dictionary import BIDSDataDictFile

T = TypeVar('T', bound=BaseModel)


class BIDSTSVFile(Generic[T]):
    """
    Class for a BIDS TSV file.

    Documentation:
    https://bids-specification.readthedocs.io/en/stable/common-principles.html#tabular-files
    """

    path: Path
    model_class: type[T]
    dictionary: BIDSDataDictFile | None
    rows: list[T]

    def __init__(self, model_class: type[T], path: Path):
        self.path = path
        self.model_class = model_class
        self.rows = []
        self.dictionary = None

        dictionary_path = replace_path_extension(self.path, 'json')
        if dictionary_path.exists():
            self.dictionary = BIDSDataDictFile(dictionary_path)
        else:
            self.dictionary = None

        with open(self.path) as file:
            reader = csv.DictReader(file, delimiter='\t')
            for row in reader:
                self.rows.append(model_class(**row))

    def get_field_names(self) -> list[str]:
        """
        Get the names of the fields of this file.
        """

        return list(self.model_class.model_fields.keys())

    def get_populated_field_names(self) -> list[str]:
        """
        Get the names of the fields that have at least one value in one row in this file.
        """

        fields             = self.get_field_names()
        unpopulated_fields = self.get_unpopulated_field_names()
        return [field for field in fields if field not in unpopulated_fields]

    def get_unpopulated_field_names(self) -> set[str]:
        """
        Get the names of the fields that do not have any value in any row in this file.
        """

        fields = set(self.get_field_names())
        for row in self.rows:
            row_dict = row.model_dump()
            for field in list(fields):
                if row_dict.get(field) is not None:
                    fields.remove(field)

        return fields

    def write(self, path: Path, fields: list[str] | None = None):
        """
        Write the TSV file to a path, writing either given fields, or the populated fields by
        default.
        """

        if fields is None:
            fields = self.get_populated_field_names()

        with open(path, 'w', newline='') as file:
            writer = csv.DictWriter(file, fieldnames=fields, delimiter='\t')
            writer.writeheader()

            for row in self.rows:
                row_dict = row.model_dump()
                filtered_row = {key: value for key, value in row_dict.items() if key in fields}
                writer.writerow(filtered_row)

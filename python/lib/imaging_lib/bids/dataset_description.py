import json
from pathlib import Path
from typing import Any


class BidsDatasetDescriptionError(ValueError):
    """
    Error raised when reading an incorrect BIDS dataset description file.
    """

    def __init__(self, message: str):
        super().__init__(message)


class BidsDatasetDescription:
    """
    Information about the contents of a BIDS dataset description file.
    """

    name: str
    """
    The BIDS dataset name.
    """

    bids_version: str
    """
    The BIDS dataset BIDS version.
    """

    json: dict[str, Any]
    """
    The BIDS dataset description JSON data.
    """

    def __init__(self, dataset_descrption_path: Path):
        """
        Read a BIDS dataset description file, or raise an exception if that file contains incorrect
        data.
        """

        with open(dataset_descrption_path) as dataset_description_file:
            try:
                self.json = json.load(dataset_description_file)
            except ValueError:
                raise BidsDatasetDescriptionError("The BIDS dataset description file does not contain valid JSON.")

        try:
            self.name = self.json["Name"]
        except ValueError:
            raise BidsDatasetDescriptionError("Missing property 'Name' in the BIDS dataset description file.")

        try:
            self.bids_version = self.json["BIDSVersion"]
        except ValueError:
            raise BidsDatasetDescriptionError("Missing property 'BIDSVersion' in the BIDS dataset description file.")

import json
from pathlib import Path
from typing import Any


class BidsJsonFile:
    """
    Class representing a BIDS JSON file.
    """

    path: Path
    data: dict[str, Any]

    def __init__(self, path: Path):
        self.path = path
        with open(path) as file:
            data = json.load(file)
            self.validate_data(data)
            self.data = data

    def validate_data(self, data: dict[str, Any]):
        """
        Validate the JSON data for this file.
        """

        pass

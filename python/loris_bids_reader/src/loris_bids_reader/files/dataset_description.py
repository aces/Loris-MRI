from typing import Any

from loris_bids_reader.json import BidsJsonFile


class BidsDatasetDescriptionJsonFile(BidsJsonFile):
    """
    Class representing a BIDS dataset_description.json file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/dataset-description.html#dataset_descriptionjson
    """

    def validate_data(self, data: dict[str, Any]):
        if 'Name' not in data:
            raise Exception("Missing required field 'Name' in dataset_description.json.")

        if 'BIDSVersion' not in data:
            raise Exception("Missing required field 'BIDSVersion' in dataset_description.json.")

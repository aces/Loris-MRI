import re
from collections.abc import Iterator
from functools import cached_property
from pathlib import Path

from lib.imaging_lib.bids.dataset import BIDSDataType


class BIDSMEGDataType(BIDSDataType):
    @cached_property
    def acquisitions(self) -> list['BIDSMEGAcquisition']:
        """
        The MEG acquisitions found in the MEG data type.
        """

        acquisitions: list[BIDSMEGAcquisition] = []
        for acquisition_name in find_dir_meg_acquisition_names(self.path):
            acquisitions.append(BIDSMEGAcquisition(self, acquisition_name))

        return acquisitions


class BIDSMEGAcquisition:
    data_type: BIDSMEGDataType
    name: str
    sidecar_path: Path

    def __init__(self, data_type: BIDSMEGDataType, name: str):
        self.data_type    = data_type
        self.name         = name
        self.sidecar_path = (self.data_type.path / name).with_suffix('.json')


def find_dir_meg_acquisition_names(dir_path: Path) -> Iterator[str]:
    """
    Iterate over the Path objects of the NIfTI files found in a directory.
    """

    for item_path in dir_path.iterdir():
        name_match = re.search(r'(.+_meg)\.json', item_path.name)
        if name_match is not None:
            yield name_match.group(1)

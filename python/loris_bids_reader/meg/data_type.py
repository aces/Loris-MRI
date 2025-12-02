import re
from collections.abc import Iterator
from functools import cached_property
from pathlib import Path

from loris_bids_reader.agnostic.events import BIDSEventsFile
from loris_bids_reader.dataset import BIDSDataType
from loris_bids_reader.meg.channels import BIDSMEGChannelsFile
from loris_bids_reader.meg.sidecar import BIDSMEGSidecarFile


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
    path: Path
    sidecar: BIDSMEGSidecarFile
    channels: BIDSMEGChannelsFile | None
    events: BIDSEventsFile | None

    def __init__(self, data_type: BIDSMEGDataType, name: str):
        self.data_type    = data_type
        self.path         = self.data_type.path / name
        sidecar_path      = self.path.with_suffix('.json')
        if not sidecar_path.exists():
            raise Exception("No MEG JSON sidecar file.")

        self.sidecar = BIDSMEGSidecarFile(sidecar_path)

        channels_path = self.path.parent / re.sub(r'_meg$', '_channels.tsv', self.path.name)
        self.channels = BIDSMEGChannelsFile(channels_path) if channels_path.exists() else None

        events_path = self.path.parent / re.sub(r'_meg$', '_events.tsv', self.path.name)
        self.events = BIDSEventsFile(events_path) if events_path.exists() else None

    @property
    def name(self) -> str:
        return self.path.name


def find_dir_meg_acquisition_names(dir_path: Path) -> Iterator[str]:
    """
    Iterate over the Path objects of the NIfTI files found in a directory.
    """

    for item_path in dir_path.iterdir():
        name_match = re.search(r'(.+_meg)\.ds$', item_path.name)
        if name_match is not None:
            yield name_match.group(1)

import re
from collections.abc import Iterator, Sequence
from functools import cached_property
from pathlib import Path

from loris_bids_reader.dataset import BidsAcquisition, BidsDataType
from loris_bids_reader.eeg.channels import BidsEegChannelsTsvFile
from loris_bids_reader.files.events import BidsEventsTsvFile
from loris_bids_reader.meg.sidecar import BidsMegSidecarJsonFile


class BidsMegDataType(BidsDataType):
    @cached_property
    def acquisitions(self) -> Sequence['BidsMegAcquisition']:
        """
        The MEG acquisitions found in the MEG data type.
        """

        acquisitions: list[BidsMegAcquisition] = []
        for acquisition_name in find_dir_meg_acquisition_names(self.path):
            acquisitions.append(BidsMegAcquisition(self, acquisition_name))

        return acquisitions


class BidsMegAcquisition(BidsAcquisition):
    ctf_path: Path
    sidecar: BidsMegSidecarJsonFile
    channels: BidsEegChannelsTsvFile | None
    events: BidsEventsTsvFile | None

    def __init__(self, data_type: BidsMegDataType, name: str):
        super().__init__(data_type, name)

        self.ctf_path = self.path.with_name(f'{name}.ds')

        sidecar_path = self.path.with_suffix('.json')
        if not sidecar_path.exists():
            raise Exception("No MEG JSON sidecar file.")

        self.sidecar = BidsMegSidecarJsonFile(sidecar_path)

        channels_path = self.path.parent / re.sub(r'_meg$', '_channels.tsv', self.path.name)
        self.channels = BidsEegChannelsTsvFile(channels_path) if channels_path.exists() else None

        events_path = self.path.parent / re.sub(r'_meg$', '_events.tsv', self.path.name)
        self.events = BidsEventsTsvFile(events_path) if events_path.exists() else None


def find_dir_meg_acquisition_names(dir_path: Path) -> Iterator[str]:
    """
    Iterate over the Path objects of the NIfTI files found in a directory.
    """

    for item_path in dir_path.iterdir():
        name_match = re.search(r'(.+_meg)\.ds$', item_path.name)
        if name_match is not None:
            yield name_match.group(1)

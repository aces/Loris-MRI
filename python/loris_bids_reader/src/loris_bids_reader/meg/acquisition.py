
import re
from pathlib import Path

from loris_bids_reader.eeg.channels import BidsEegChannelsTsvFile
from loris_bids_reader.files.events import BidsEventsTsvFile
from loris_bids_reader.meg.sidecar import BidsMegSidecarJsonFile


class MegAcquisition:
    ctf_path: Path
    sidecar: BidsMegSidecarJsonFile
    channels: BidsEegChannelsTsvFile | None
    events: BidsEventsTsvFile | None

    def __init__(self, path: Path, name: str):
        self.path = path

        self.ctf_path = self.path.with_name(f'{name}.ds')

        sidecar_path = self.path.with_suffix('.json')
        if not sidecar_path.exists():
            raise Exception("No MEG JSON sidecar file.")

        self.sidecar = BidsMegSidecarJsonFile(sidecar_path)

        channels_path = self.path.parent / re.sub(r'_meg$', '_channels.tsv', self.path.name)
        self.channels = BidsEegChannelsTsvFile(channels_path) if channels_path.exists() else None

        events_path = self.path.parent / re.sub(r'_meg$', '_events.tsv', self.path.name)
        self.events = BidsEventsTsvFile(events_path) if events_path.exists() else None

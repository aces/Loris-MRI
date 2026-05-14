
import re
from pathlib import Path

from loris_utils.path import remove_path_extension

from loris_bids_reader.eeg.channels import BidsEegChannelsTsvFile
from loris_bids_reader.files.events import BidsEventsTsvFile
from loris_bids_reader.meg.head_shape import MegCtfHeadShapeFile
from loris_bids_reader.meg.sidecar import BidsMegSidecarJsonFile


class MegAcquisition:
    ctf_path: Path
    sidecar_file: BidsMegSidecarJsonFile
    channels_file: BidsEegChannelsTsvFile | None
    events_file: BidsEventsTsvFile | None
    head_shape_file: MegCtfHeadShapeFile | None

    def __init__(self, ctf_path: Path, head_shape_file: MegCtfHeadShapeFile | None):
        self.ctf_path = ctf_path

        path = remove_path_extension(ctf_path)

        sidecar_path = path.with_suffix('.json')
        if not sidecar_path.exists():
            raise Exception("No MEG JSON sidecar file.")

        self.sidecar_file = BidsMegSidecarJsonFile(sidecar_path)

        channels_path = path.parent / re.sub(r'_meg$', '_channels.tsv', path.name)
        self.channels_file = BidsEegChannelsTsvFile(channels_path) if channels_path.exists() else None

        events_path = path.parent / re.sub(r'_meg$', '_events.tsv', path.name)
        self.events_file = BidsEventsTsvFile(events_path) if events_path.exists() else None

        self.head_shape_file = head_shape_file

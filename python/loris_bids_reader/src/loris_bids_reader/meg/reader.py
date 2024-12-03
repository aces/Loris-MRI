import re
from collections.abc import Iterator, Sequence
from functools import cached_property
from pathlib import Path

from loris_bids_reader.info import BidsAcquisitionInfo
from loris_bids_reader.meg.acquisition import MegAcquisition
from loris_bids_reader.reader import BidsDataTypeReader


class BidsMegDataTypeReader(BidsDataTypeReader):
    path: Path

    @cached_property
    def acquisitions(self) -> Sequence[tuple[MegAcquisition, BidsAcquisitionInfo]]:
        """
        The MEG acquisitions found in the MEG data type.
        """

        acquisitions: list[tuple[MegAcquisition, BidsAcquisitionInfo]] = []
        for acquisition_name in find_dir_meg_acquisition_names(self.path):
            scan_row = self.session.scans_file.get_row(self.path / acquisition_name) \
                if self.session.scans_file is not None else None
            acquisition = MegAcquisition(self.path, acquisition_name)
            info = BidsAcquisitionInfo(
                subject         = self.session.subject.label,
                participant_row = self.session.subject.participant_row,
                session         = self.session.label,
                scans_file      = self.session.scans_file,
                data_type       = self.name,
                scan_row        = scan_row,
                name            = acquisition_name,
                suffix          = 'meg',
            )

            acquisitions.append((acquisition, info))

        return acquisitions


def find_dir_meg_acquisition_names(dir_path: Path) -> Iterator[str]:
    """
    Iterate over the Path objects of the NIfTI files found in a directory.
    """

    for item_path in dir_path.iterdir():
        name_match = re.search(r'(.+_meg)\.ds$', item_path.name)
        if name_match is not None:
            yield name_match.group(1)

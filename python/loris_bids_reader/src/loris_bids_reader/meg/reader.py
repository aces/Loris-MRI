import re
from collections.abc import Iterator
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

from loris_bids_reader.info import BidsAcquisitionInfo
from loris_bids_reader.meg.acquisition import MegAcquisition
from loris_bids_reader.meg.head_shape import MegCtfHeadShapeFile
from loris_bids_reader.reader import BidsDataTypeReader
from loris_bids_reader.utils import get_pybids_file_path, try_get_pybids_value


@dataclass
class BidsMegDataTypeReader(BidsDataTypeReader):
    path: Path

    @cached_property
    def acquisitions(self) -> list[tuple[MegAcquisition, BidsAcquisitionInfo]]:
        """
        The MEG acquisitions found in the MEG data type.
        """

        acquisitions: list[tuple[MegAcquisition, BidsAcquisitionInfo]] = []
        for ctf_name in find_dir_meg_acquisition_names(self.path):
            scan_row = self.session.scans_file.get_row(self.path / ctf_name) \
                if self.session.scans_file is not None else None

            acquisition = MegAcquisition(self.path / ctf_name, self.head_shape_file)

            info = BidsAcquisitionInfo(
                subject         = self.session.subject.label,
                participant_row = self.session.subject.participant_row,
                session         = self.session.label,
                scans_file      = self.session.scans_file,
                data_type       = self.name,
                scan_row        = scan_row,
                name            = ctf_name,
                suffix          = 'meg',
            )

            acquisitions.append((acquisition, info))

        return acquisitions

    @cached_property
    def head_shape_file(self) -> MegCtfHeadShapeFile | None:
        """
        The MEG CTF file of this acquisition if it exists.
        """

        head_shape_file = try_get_pybids_value(
            self.session.subject.dataset.layout,
            subject=self.session.subject.label,
            session=self.session.label,
            datatype=self.name,
            suffix='headshape',
            extension='.pos',
        )

        if head_shape_file is None:
            return None

        return MegCtfHeadShapeFile(get_pybids_file_path(head_shape_file))


def find_dir_meg_acquisition_names(dir_path: Path) -> Iterator[str]:
    """
    Iterate over the Path objects of the NIfTI files found in a directory.
    """

    for item_path in dir_path.iterdir():
        name_match = re.search(r'.+_meg\.ds$', item_path.name)
        if name_match is not None:
            yield name_match.group(0)

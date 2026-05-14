from collections.abc import Sequence
from functools import cached_property

from loris_bids_reader.info import BidsAcquisitionInfo
from loris_bids_reader.reader import BidsDataTypeReader


class BidsEegDataTypeReader(BidsDataTypeReader):
    @cached_property
    def acquisitions(self) -> Sequence[BidsAcquisitionInfo]:
        return []

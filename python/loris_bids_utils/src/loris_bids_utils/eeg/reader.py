from collections.abc import Sequence
from functools import cached_property

from loris_bids_utils.info import BidsAcquisitionInfo
from loris_bids_utils.reader import BidsDataTypeReader


class BidsEegDataTypeReader(BidsDataTypeReader):
    @cached_property
    def acquisitions(self) -> Sequence[BidsAcquisitionInfo]:
        return []

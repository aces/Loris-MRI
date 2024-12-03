from collections.abc import Sequence
from functools import cached_property

from loris_bids_reader.dataset import BidsAcquisition, BidsDataType


class BidsEegDataType(BidsDataType):
    @cached_property
    def acquisitions(self) -> Sequence[BidsAcquisition]:
        return []

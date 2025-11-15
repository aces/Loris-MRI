from collections.abc import Sequence
from functools import cached_property
from typing import Self

from loris_bids_reader.dataset import BIDSAcquisition, BIDSDataType


class BIDSEEGDataType(BIDSDataType):
    @cached_property
    def acquisitions(self) -> Sequence[BIDSAcquisition[Self]]:
        return []

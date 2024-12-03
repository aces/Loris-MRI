import re
from collections.abc import Sequence
from functools import cached_property
from pathlib import Path

from lib.util.path import remove_path_extension, replace_path_extension

from loris_bids_reader.dataset import BidsAcquisition, BidsDataType
from loris_bids_reader.mri.sidecar import BidsMriSidecarJsonFile


class BidsMriDataType(BidsDataType):
    @cached_property
    def acquisitions(self) -> Sequence['BidsMriAcquisition']:
        acquisitions: list[BidsMriAcquisition] = []

        for file_path in self.path.iterdir():
            if file_path.name.endswith(('.nii', '.nii.gz')):
                acquisitions.append(BidsMriAcquisition(self, file_path))

        return acquisitions


class BidsMriAcquisition(BidsAcquisition):
    nifti_path: Path
    sidecar: BidsMriSidecarJsonFile | None
    bval_path: Path | None
    bvec_path: Path | None
    suffix: str | None

    def __init__(self, data_type: BidsMriDataType, nifti_path: Path):
        super().__init__(data_type, remove_path_extension(nifti_path).name)
        self.nifti_path = data_type.path / nifti_path

        sidecar_path = replace_path_extension(self.path, 'json')
        self.sidecar = BidsMriSidecarJsonFile(sidecar_path) if sidecar_path.exists() else None

        bval_path = replace_path_extension(self.path, 'bval')
        self.bval_path = bval_path if bval_path.exists() else None

        bvec_path = replace_path_extension(self.path, 'bvec')
        self.bvec_path = bvec_path if bvec_path.exists() else None

        suffix_match = re.search(r'_([a-zA-Z0-9]+)$', self.name)
        self.suffix = suffix_match.group(1) if suffix_match is not None else None

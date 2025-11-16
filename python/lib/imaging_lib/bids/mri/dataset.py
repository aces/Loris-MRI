import re
from functools import cached_property
from pathlib import Path

from lib.imaging_lib.bids.dataset import BIDSDataset, BIDSDataType, BIDSSession, BIDSSubject
from lib.util.fs import remove_path_extension, replace_path_extension


class BIDSMRIDataType(BIDSDataType):
    @cached_property
    def niftis(self) -> list['BIDSMRIAcquisition']:
        """
        The NIfTI files found in this MRI data type directory.
        """

        acquisitions: list[BIDSMRIAcquisition] = []

        for file_path in self.path.iterdir():
            if file_path.name.endswith(('.nii', '.nii.gz')):
                acquisitions.append(BIDSMRIAcquisition(self, file_path))

        return acquisitions


class BIDSMRIAcquisition:
    data_type: BIDSDataType
    path: Path
    nifti_path: Path
    sidecar_path: Path | None
    bval_path: Path | None
    bvec_path: Path | None
    suffix: str | None

    def __init__(self, data_type: BIDSDataType, nifti_path: Path):
        self.data_type  = data_type
        self.path       = remove_path_extension(nifti_path)
        self.nifti_path = data_type.path / nifti_path

        sidecar_path = replace_path_extension(self.path, 'json')
        self.sidecar_path = sidecar_path if sidecar_path.exists() else None

        bval_path = replace_path_extension(self.path, 'bval')
        self.bval_path = bval_path if bval_path.exists() else None

        bvec_path = replace_path_extension(self.path, 'bvec')
        self.bvec_path = bvec_path if bvec_path.exists() else None

        suffix_match = re.search(r'_([a-zA-Z0-9]+)$', self.name)
        self.suffix = suffix_match.group(1) if suffix_match is not None else None

    @property
    def name(self):
        return self.path.name

    @property
    def root_dataset(self) -> BIDSDataset:
        return self.data_type.root_dataset

    @property
    def subject(self) -> BIDSSubject:
        return self.data_type.subject

    @property
    def session(self) -> BIDSSession:
        return self.data_type.session

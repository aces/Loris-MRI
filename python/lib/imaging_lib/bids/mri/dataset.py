import re
from functools import cached_property
from pathlib import Path

from lib.imaging_lib.bids.dataset import BIDSDataset, BIDSDataType, BIDSSession, BIDSSubject
from lib.imaging_lib.nifti import find_dir_nifti_files
from lib.util.fs import replace_file_extension


class BIDSMRIDataType(BIDSDataType):
    @cached_property
    def niftis(self) -> list['BIDSNifti']:
        """
        The NIfTI files found in this MRI data type directory.
        """

        niftis: list[BIDSNifti] = []

        for nifti_path in find_dir_nifti_files(self.path):
            niftis.append(BIDSNifti(self, nifti_path.name))

        return niftis


class BIDSNifti:
    data_type: BIDSDataType
    path: Path
    suffix: str | None

    def __init__(self, data_type: BIDSDataType, name: str):
        self.data_type = data_type
        self.path      = data_type.path / name

        suffix_match = re.search(r'_([a-zA-Z0-9]+)\.nii(\.gz)?$', self.name)
        if suffix_match is not None:
            self.suffix = suffix_match.group(1)
        else:
            self.suffix = None

    @property
    def name(self) -> str:
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

    def get_json_path(self) -> Path | None:
        """
        Get the JSON sidecar file path of this NIfTI file if it exists.
        """

        json_name = replace_file_extension(self.name, 'json')
        json_path = self.data_type.path / json_name
        if not json_path.exists():
            return None

        return json_path

    def get_bval_path(self) -> Path | None:
        """
        Get the BVAL file path of this NIfTI file if it exists.
        """

        bval_name = replace_file_extension(self.name, 'bval')
        bval_path = self.data_type.path / bval_name
        if not bval_path.exists():
            return None

        return bval_path

    def get_bvec_path(self) -> Path | None:
        """
        Get the BVEC file path of this NIfTI file if it exists.
        """

        bvec_name = replace_file_extension(self.name, 'bvec')
        bvec_path = self.data_type.path / bvec_name
        if not bvec_path.exists():
            return None

        return bvec_path

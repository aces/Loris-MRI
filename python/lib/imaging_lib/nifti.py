import os
from collections.abc import Iterator
from typing import Any, cast

import nibabel as nib


def add_nifti_file_parameters(nifti_path: str, nifti_file_hash: str, file_parameters: dict[str, Any]):
    """
    Read a NIfTI image and add some of its properties to the file parameters.
    """

    img = nib.load(nifti_path)  # type: ignore

    # Add the voxel step parameters from the NIfTI file header.
    zooms = cast(tuple[float, ...], img.header.get_zooms())  # type: ignore
    file_parameters['xstep'] = zooms[0]
    file_parameters['ystep'] = zooms[1]
    file_parameters['zstep'] = zooms[2]

    # Add the time length parameters from the NIfTI file header.
    shape = cast(tuple[int, ...], img.shape)  # type: ignore
    file_parameters['xspace'] = shape[0]
    file_parameters['yspace'] = shape[1]
    file_parameters['zspace'] = shape[2]
    if len(shape) == 4:
        file_parameters['time'] = shape[3]

    # Add the file BLAKE2b hash.
    file_parameters['file_blake2b_hash'] = nifti_file_hash


def find_dir_nifti_names(dir_path: str) -> Iterator[str]:
    """
    Iterate over the names of the NIfTI files found in a directory.
    """

    for file_name in os.listdir(dir_path):
        if file_name.endswith(('.nii', '.nii.gz')):
            yield file_name

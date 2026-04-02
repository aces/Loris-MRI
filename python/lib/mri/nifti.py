from pathlib import Path
from typing import Any, cast

import nibabel as nib


def add_nifti_spatial_file_parameters(nifti_path: Path, file_parameters: dict[str, Any]):
    """
    Read a NIfTI image and add its spatial properties to the file parameters dictionary.
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

    # Add the time parameter if the image is a 4D dataset.
    if len(shape) == 4:
        file_parameters['time'] = shape[3]
    else:
        file_parameters['time'] = None

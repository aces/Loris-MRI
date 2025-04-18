from dataclasses import dataclass
from typing import cast

import nibabel as nib


@dataclass
class ImageStepParameters:
    x_step: float
    y_step: float
    z_step: float


def get_nifti_image_step_parameters(nifti_path: str) -> ImageStepParameters:
    """
    Get the step information (xstep, ystep, zstep and number of volumes for a 4D dataset) of a
    NIfTI image.
    """

    img = nib.load(nifti_path)  # type: ignore

    # Get the voxel step/time step of the image.
    zooms = cast(tuple[float, ...], img.header.get_zooms())  # type: ignore

    return ImageStepParameters(
        x_step = zooms[0],
        y_step = zooms[1],
        z_step = zooms[1],
    )


@dataclass
class ImageLengthParameters:
    x_space: int
    y_space: int
    z_space: int
    time: int | None


def get_nifti_image_length_parameters(nifti_path: str) -> ImageLengthParameters:
    """
    Get the length dimensions (x, y, z and time for a 4D dataset) of a NIfTI image.
    """

    img = nib.load(nifti_path)  # type: ignore

    # Get the voxel/time length array of the image.
    shape = cast(tuple[int, ...], img.shape)  # type: ignore

    return ImageLengthParameters(
        x_space = shape[0],
        y_space = shape[1],
        z_space = shape[2],
        time = shape[3] if len(shape) == 4 else None
    )

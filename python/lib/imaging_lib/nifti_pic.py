import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast

import nibabel as nib
import numpy as np
from matplotlib import pyplot as plt
from nibabel.orientations import io_orientation  # type: ignore

from lib.config import get_data_dir_path_config
from lib.db.models.file import DbFile
from lib.env import Env
from lib.imaging_lib.file_parameter import register_mri_file_parameter

DISPLAY_AXES = (
    # Fixed world axis, horizontal world axis, vertical world axis.
    (0, 1, 2),  # Sagittal: anterior/posterior x inferior/superior.
    (1, 0, 2),  # Coronal:  left/right x inferior/superior.
    (2, 0, 1),  # Axial:    left/right x posterior/anterior.
)


@dataclass
class PreviewSlice:
    """
    A preview slice and its physical height-to-width pixel ratio.
    """

    data: np.ndarray
    aspect: float


def create_nifti_preview_picture(env: Env, nifti_file: DbFile) -> Path:
    """
    Create the preview picture that is displayed to the user in the imaging browser view session
    page. The path returned is relative to the `data_dir/pic` directory.
    """

    data_dir_path = get_data_dir_path_config(env)

    cand_id = nifti_file.session.candidate.cand_id
    nifti_path = data_dir_path / nifti_file.path

    pic_name = re.sub(r'\.nii(\.gz)?$', f'_{nifti_file.id}_check.png', nifti_file.path.name)
    pic_path = data_dir_path / 'pic' / str(cand_id) / pic_name

    # Create the candidate picture directory if it does not already exist.
    pic_path.parent.mkdir(exist_ok=True)

    image = nib.load(nifti_path)  # type: ignore
    if is_rgb_nifti(image):
        create_rgb_nifti_preview_picture(image, pic_path)
    else:
        create_scalar_nifti_preview_picture(image, pic_path)

    pic_rel_path = pic_path.relative_to(data_dir_path / 'pic')
    register_mri_file_parameter(env, nifti_file, 'check_pic_filename', str(pic_rel_path))
    env.db.commit()

    return pic_rel_path


def is_rgb_nifti(image: Any) -> bool:
    """
    Return whether a NIfTI image stores RGB voxels.
    """

    fields = image.get_data_dtype().fields
    return fields is not None and {'R', 'G', 'B'}.issubset(fields)


def create_rgb_nifti_preview_picture(image: Any, pic_path: Path):
    """
    Create an RGB preview while loading only three orthogonal slices into memory.
    """

    slices = [
        PreviewSlice(get_rgb_array(preview_slice.data), preview_slice.aspect)
        for preview_slice in get_preview_slices(image)
    ]

    save_preview_slices(slices, pic_path)


def create_scalar_nifti_preview_picture(image: Any, pic_path: Path):
    """
    Create a grayscale preview while loading only three orthogonal slices into memory.
    """

    slices = [
        PreviewSlice(get_nifti_plotting_data(preview_slice.data), preview_slice.aspect)
        for preview_slice in get_preview_slices(image)
    ]

    vmin, vmax = get_scalar_display_range([preview_slice.data for preview_slice in slices])
    save_preview_slices(slices, pic_path, cmap='gray', vmin=vmin, vmax=vmax)


def save_preview_slices(slices: list[PreviewSlice], pic_path: Path, **imshow_kwargs: Any):
    """
    Render three prepared orthogonal slices to a preview picture.
    """

    figure, axes = plt.subplots(1, 3, figsize=(9, 3), facecolor='black')
    for axis, preview_slice in zip(axes, slices, strict=True):
        axis.imshow(
            preview_slice.data,
            aspect=preview_slice.aspect,
            interpolation='nearest',
            origin='lower',
            **imshow_kwargs,
        )
        axis.set_axis_off()
        axis.set_facecolor('black')

    figure.subplots_adjust(left=0, right=1, bottom=0, top=1, wspace=0.02)
    figure.savefig(pic_path, facecolor='black', bbox_inches='tight', pad_inches=0)  # type: ignore
    plt.close(figure)


def get_preview_slices(image: Any) -> list[PreviewSlice]:
    """
    Load and orient the three center slices used in a preview.
    """

    shape = cast(tuple[int, ...], image.shape)
    if len(shape) not in (3, 4):
        raise ValueError(f'Unsupported RGB NIfTI dimensions: {shape}')

    orientation = np.asarray(io_orientation(image.affine))  # type: ignore
    voxel_sizes = image.header.get_zooms()[:3]
    slices: list[PreviewSlice] = []

    for fixed_world_axis, horizontal_world_axis, vertical_world_axis in DISPLAY_AXES:
        fixed_voxel_axis = int(np.flatnonzero(orientation[:, 0] == fixed_world_axis)[0])
        horizontal_voxel_axis = int(np.flatnonzero(orientation[:, 0] == horizontal_world_axis)[0])
        vertical_voxel_axis = int(np.flatnonzero(orientation[:, 0] == vertical_world_axis)[0])
        data = load_center_slice(image, fixed_voxel_axis, shape)
        data = orient_slice(
            data,
            fixed_voxel_axis,
            horizontal_world_axis,
            vertical_world_axis,
            orientation,
        )
        slices.append(PreviewSlice(
            data=data,
            aspect=voxel_sizes[vertical_voxel_axis] / voxel_sizes[horizontal_voxel_axis],
        ))

    return slices


def load_center_slice(image: Any, voxel_axis: int, shape: tuple[int, ...]) -> np.ndarray:
    """
    Load one center slice, using only the first volume when the image is 4D.
    """

    indices: list[int | slice] = [slice(None)] * len(shape)
    indices[voxel_axis] = shape[voxel_axis] // 2
    if len(shape) == 4:
        indices[3] = 0

    return np.asanyarray(image.dataobj[tuple(indices)])


def orient_slice(
    data: np.ndarray,
    fixed_voxel_axis: int,
    horizontal_world_axis: int,
    vertical_world_axis: int,
    orientation: np.ndarray,
) -> np.ndarray:
    """
    Transpose and flip a voxel slice into the requested world-axis display orientation.
    """

    remaining_voxel_axes = [axis for axis in range(3) if axis != fixed_voxel_axis]

    def get_slice_axis(world_axis: int) -> int:
        return next(
            slice_axis
            for slice_axis, voxel_axis in enumerate(remaining_voxel_axes)
            if orientation[voxel_axis, 0] == world_axis
        )

    horizontal_axis = get_slice_axis(horizontal_world_axis)
    vertical_axis = get_slice_axis(vertical_world_axis)
    oriented_data = np.transpose(data, (vertical_axis, horizontal_axis))

    # Make both displayed axes increase in world coordinates. Matplotlib uses origin='lower'.
    if orientation[remaining_voxel_axes[vertical_axis], 1] < 0:
        oriented_data = np.flip(oriented_data, axis=0)
    if orientation[remaining_voxel_axes[horizontal_axis], 1] < 0:
        oriented_data = np.flip(oriented_data, axis=1)

    return oriented_data


def get_rgb_array(data: np.ndarray) -> np.ndarray:
    """
    Convert a structured RGB voxel array to an array displayable by Matplotlib.
    """

    rgb = np.stack([data[channel] for channel in ('R', 'G', 'B')], axis=-1)
    if rgb.dtype == np.uint8:
        return rgb

    rgb = rgb.astype(np.float32)
    maximum = float(np.max(rgb, initial=0))
    if maximum > 1:
        rgb /= maximum

    return np.clip(rgb, 0, 1)


def get_nifti_plotting_data(data: np.ndarray) -> np.ndarray:
    """
    Convert scalar NIfTI voxel data to a float array suitable for plotting.
    """

    return data.astype(np.float32, copy=False)


def get_scalar_display_range(slices: list[np.ndarray]) -> tuple[float, float]:
    """
    Calculate a robust shared intensity range for three scalar preview slices.
    """

    finite_values = np.concatenate([data[np.isfinite(data)] for data in slices])
    nonzero_values = finite_values[finite_values != 0]
    values = nonzero_values if nonzero_values.size else finite_values
    if not values.size:
        return 0, 1

    vmin, vmax = np.percentile(values, (1, 99))
    if vmin == vmax:
        return min(0, float(vmin)), max(1, float(vmax))

    return float(vmin), float(vmax)

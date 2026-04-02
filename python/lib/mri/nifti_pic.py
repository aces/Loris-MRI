import re
from pathlib import Path

import nibabel as nib
import numpy as np
from nibabel.nifti1 import Nifti1Image
from nilearn import plotting

from lib.config import get_data_dir_path_config
from lib.db.models.file import DbFile
from lib.env import Env


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

    img = nib.load(nifti_path)  # type: ignore

    if len(img.shape) == 4:  # type: ignore
        # Only load the first 3D slice of a 4D image.
        data = img.dataobj[..., 0]  # type: ignore
    else:
        # Load the full data for a 3D image.
        data = img.dataobj[...]  # type: ignore

    # Explicitely load the volume as float32 for plotting.
    volume = Nifti1Image(
        data.astype(np.float32, copy=False),  # type: ignore
        img.affine,  # type: ignore
    )

    plotting.plot_anat(  # type: ignore
        anat_img=volume,
        output_file=pic_path,
        display_mode='ortho',
        black_bg=True,  # type: ignore
        draw_cross=False,
        annotate=False,
    )

    return pic_path.relative_to(data_dir_path / 'pic')

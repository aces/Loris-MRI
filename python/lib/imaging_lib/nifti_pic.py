import os
import re

import nibabel as nib
import numpy as np
from nibabel.nifti1 import Nifti1Image
from nilearn import plotting

from lib.config import get_data_dir_path_config
from lib.db.models.file import DbFile
from lib.env import Env


def create_imaging_pic(env: Env, file: DbFile, is_4d_data: bool) -> str:
    """
    Creates the preview pic that will show in the imaging browser view session
    page. This pic will be stored in the data_dir/pic folder

    :param file_info: dictionary with file information (path, file_id, cand_id...)
        :type file_info: dict
    :param pic_rel_path: relative path to the pic to use if one provided. Otherwise
                            create_imaging_pic will automatically generate the pic name
                            based on the file path of the NIfTI file
        :type pic_rel_path: str

    :return: path to the created pic
        :rtype: str
    """

    data_dir_path = get_data_dir_path_config(env)

    cand_id = file.session.candidate.cand_id
    file_path = os.path.join(data_dir_path, file.rel_path)

    pic_name = re.sub(r"\.nii(\.gz)?$", f'_{file.id}_check.png', os.path.basename(file.rel_path))
    pic_rel_path = os.path.join(str(cand_id), pic_name)
    pic_dir_path = os.path.join(data_dir_path, 'pic', str(cand_id))
    pic_path = os.path.join(data_dir_path, 'pic', pic_rel_path)

    # create the candID directory where the pic will go if it does not already exist
    if not os.path.exists(pic_dir_path):
        os.mkdir(pic_dir_path)

    img = nib.load(file_path)  # type: ignore

    if is_4d_data:
        # Only load the first slice of a 4D image.
        data = img.dataobj[..., 0]  # type: ignore
    else:
        data = img.dataobj[...]  # type: ignore

    # Load the image as float32 for plotting.
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

    return pic_rel_path

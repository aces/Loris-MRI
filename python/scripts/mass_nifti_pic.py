#!/usr/bin/env python

"""Script to mass create the pic images of inserted NIfTI files."""

import argparse
from pathlib import Path

from loris_utils.path import get_path_extension

import lib.exitcode
from lib.config import get_data_dir_path_config
from lib.config_file import load_config
from lib.db.queries.file import try_get_file_with_id
from lib.db.queries.file_parameter import try_get_parameter_value_with_file_id_parameter_name
from lib.env import Env
from lib.imaging_lib.nifti_pic import create_nifti_preview_picture
from lib.logging import log, log_error, log_error_exit, log_warning
from lib.make_env import make_env


def main():
    parser = argparse.ArgumentParser(
        description="Mass create pic images for inserted NIfTI files.",
    )

    parser.add_argument(
        '-p', '--profile',
        help="Name of the python database config file in the config directory."
    )

    parser.add_argument(
        '-s', '--smallest-id',
        type=int,
        required=True,
        help="Smallest file ID for which the pic will be created."
    )

    parser.add_argument(
        '-l', '--largest-id',
        type=int,
        required=True,
        help="Largest file ID for which the pic will be created."
    )

    parser.add_argument(
        '-f', '--force',
        action='store_true',
        help="Overwrite the pic already present in the filesystem with new pic."
    )

    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help="If set, be verbose."
    )

    args = parser.parse_args()

    config_file = load_config(args.profile)
    env = make_env('mass_nifti_pic', {}, config_file, args.verbose)

    if not (args.smallest_id <= args.largest_id):
        log_error_exit(
            env,
            "The --smallest-id value should be smaller than the --largest-id value",
            lib.exitcode.INVALID_ARG,
        )

    data_dir_path = get_data_dir_path_config(env)

    # Create pic for NIfTI files with a file ID between the smallest and largest IDs.
    for file_id in range(args.smallest_id, args.largest_id + 1):
        make_pic(env, data_dir_path, file_id, args.force)


def make_pic(env: Env, data_dir_path: Path, file_id: int, force: bool):
    """
    Call the NIfTI preview picture creation function on the provided file ID.
    """

    nifti_file = try_get_file_with_id(env.db, file_id)
    if nifti_file is None:
        log_warning(env, f"No file with ID {file_id} in the database, skipping.")
        return

    if get_path_extension(nifti_file.path) != 'nii.gz':
        log_warning(env, f"Wrong file type. File '{nifti_file.path}' is not a .nii.gz file, skipping.")
        return

    if not (data_dir_path / nifti_file.path).exists():
        log_warning(env, f"File '{nifti_file.path}' not found on the filesystem, skipping.")
        return

    # Check if there is already a preview picture for the NIfTI file.
    current_pic = try_get_parameter_value_with_file_id_parameter_name(
        env.db, file_id, 'check_pic_filename'
    )

    if current_pic is not None and not force:
        log_warning(
            env,
            f"There is already a pic for file ID {nifti_file.id}. Use -f or --force to overwrite it, skipping."
        )
        return

    log(env, f"Creating preview picture for NIfTI file ID {nifti_file.id}")

    pic_rel_path = create_nifti_preview_picture(env, nifti_file)

    pic_path = data_dir_path / 'pic' / pic_rel_path
    if not pic_path.exists():
        log_error(env, f"The pic {pic_path} was not created")
        return


if __name__ == '__main__':
    main()

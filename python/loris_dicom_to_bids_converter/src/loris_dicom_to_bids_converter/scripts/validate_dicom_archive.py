#!/usr/bin/env python

"""Validate a DICOM archive from the filesystem against its database record."""

import argparse
from pathlib import Path

from lib.config_file import load_config
from lib.make_env import make_env

from loris_dicom_to_bids_converter.dicom_archive_validation import validate_dicom_archive


def existing_path(value: str) -> Path:
    """
    Parse an existing filesystem path for a CLI argument.
    """

    path = Path(value)
    if not path.exists():
        raise argparse.ArgumentTypeError(f"{path} does not exist")

    return path


def main():
    parser = argparse.ArgumentParser(
        description="Validate a DICOM archive and update its MRI upload record.",
    )

    parser.add_argument('-p', '--profile',
        help="Name of the Python database config file in the config directory.")

    parser.add_argument('-t', '--dicom-archive-path',
        type=existing_path,
        required=True,
        help="Absolute path to the DICOM archive to validate.")

    parser.add_argument('-u', '--upload-id',
        type=int,
        required=True,
        help="ID of the MRI upload associated with the DICOM archive.")

    parser.add_argument('-v', '--verbose',
        action="store_true",
        help="Print verbose progress information.")

    args = parser.parse_args()

    profile: str | None = args.profile
    dicom_archive_path: Path = args.dicom_archive_path
    upload_id: int = args.upload_id
    verbose: bool = args.verbose

    config = load_config(profile)
    env = make_env('validate_dicom_archive', {}, config, verbose)

    try:
        validate_dicom_archive(env, dicom_archive_path, upload_id)
    finally:
        env.close()


if __name__ == '__main__':
    main()

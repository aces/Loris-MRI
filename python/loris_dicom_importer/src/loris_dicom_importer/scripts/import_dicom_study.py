#!/usr/bin/env python

import argparse
import gzip
import os
import shutil
import tarfile
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import cast

import lib.exitcode
from lib.config import get_dicom_archive_dir_path_config
from lib.config_file import load_config
from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.queries.dicom_archive import try_get_dicom_archive_with_study_instance_uid
from lib.get_session_info import SessionConfigError
from lib.logging import log, log_error_exit, log_warning
from lib.make_env import make_env
from loris_utils.fs import iter_all_dir_files

import loris_dicom_importer.text
from loris_dicom_importer.dicom_database import insert_dicom_archive, update_dicom_archive
from loris_dicom_importer.import_log import (
    make_dicom_study_import_log,
    write_dicom_study_import_log_to_file,
    write_dicom_study_import_log_to_string,
)
from loris_dicom_importer.summary_get import get_dicom_study_summary
from loris_dicom_importer.summary_util import get_dicom_study_summary_session_info
from loris_dicom_importer.summary_write import write_dicom_study_summary_to_file


@dataclass
class DicomImporterArgs:
    source: Path
    update: bool
    session: bool
    overwrite: bool
    verbose: bool


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Read a directory containing the DICOM files of a study, create a structured and "
            "compressed archive, and insert or update the study in the LORIS database."
        ),
        allow_abbrev=False,
    )
    parser.add_argument('-p', '--profile',
        help="Name of the LORIS Python configuration file (default: config.py).")
    parser.add_argument('source', type=Path,
        help="Path of the source directory containing the DICOM files of the study.")
    parser.add_argument('--overwrite', action='store_true',
        help="Overwrite the DICOM archive file if it already exists.")
    parser.add_argument('--update', action='store_true',
        help="Update an existing DICOM archive instead of inserting it, generally used with --overwrite.")
    parser.add_argument('--no-session', action='store_true',
        help="Skip association with an existing session (enabled by default using the Python configuration).")
    parser.add_argument('-v', '--verbose', action='store_true', help="Print verbose progress information.")

    args = parser.parse_args()
    if not args.source.is_dir() or not os.access(args.source, os.R_OK):
        parser.error("Argument 'source' must be a readable directory path.")

    return args


def pack_args(args: argparse.Namespace) -> DicomImporterArgs:
    return DicomImporterArgs(
        source    = args.source,
        update    = args.update,
        session   = not args.no_session,
        overwrite = args.overwrite,
        verbose   = args.verbose,
    )


def main() -> None:
    parsed_args = parse_args()
    config = load_config(parsed_args.profile)
    env = make_env('import-dicom-study', parsed_args, config, parsed_args.verbose)
    args = pack_args(parsed_args)

    # Load configuration values.

    dicom_archive_dir_path = get_dicom_archive_dir_path_config(env)

    # Utility variables.

    dicom_study_name = args.source.name

    log(env, "Extracting DICOM information... (may take a long time)")

    dicom_summary = get_dicom_study_summary(args.source, args.verbose)

    log(env, "Checking if the DICOM study is already inserted in LORIS...")

    dicom_archive = try_get_dicom_archive_with_study_instance_uid(env.db, dicom_summary.info.study_instance_uid)

    if dicom_archive is not None:
        log(env, "Found the DICOM study in LORIS.")

        if not args.update:
            log_error_exit(
                env,
                (
                    "Cannot insert the DICOM study since it is already inserted in LORIS. Use"
                    " arguments '--update' and '--overwrite' to update the currently inserted DICOM"
                    " study.\n"
                    f"Inserted DICOM study import log:\n{dicom_archive.create_info}"
                ),
                lib.exitcode.INSERT_FAILURE,
            )

    if dicom_archive is None:
        log(env, "Did not find the DICOM study in LORIS.")

        if args.update:
            log_error_exit(
                env,
                (
                    "Cannot update the DICOM study since it is not already inserted in LORIS. Omit"
                    " argument '--update' to insert the DICOM study in LORIS."
                ),
                lib.exitcode.UPDATE_FAILURE,
            )

    session = None
    if args.session:
        try:
            session_info = get_dicom_study_summary_session_info(env, dicom_summary)
        except SessionConfigError as error:
            log_error_exit(env, str(error))

        session = session_info.session

    log(env, 'Checking DICOM scan date...')

    if dicom_summary.info.scan_date is None:
        log_warning(env, "No DICOM scan date found in the DICOM files.")

        dicom_archive_rel_path = Path(f'DCM_{dicom_study_name}.tar')
    else:
        log(env, f"Found DICOM scan date: {dicom_summary.info.scan_date}")

        scan_date_string = loris_dicom_importer.text.write_date(dicom_summary.info.scan_date)
        dicom_archive_rel_path = (
            Path(str(dicom_summary.info.scan_date.year))
            / f'DCM_{scan_date_string}_{dicom_study_name}.tar'
        )

        dicom_archive_year_dir_path = dicom_archive_dir_path / str(dicom_summary.info.scan_date.year)
        if not dicom_archive_year_dir_path.exists():
            log(env, f"Creating year directory '{dicom_archive_year_dir_path}'...")
            dicom_archive_year_dir_path.mkdir()

    dicom_archive_path = dicom_archive_dir_path / dicom_archive_rel_path

    if dicom_archive_path.exists():
        if not args.overwrite:
            log_error_exit(
                env,
                f"File '{dicom_archive_path}' already exists. Use argument '--overwrite' to overwrite it",
            )

        log_warning(env, f"Overwriting file '{dicom_archive_path}'...")

        dicom_archive_path.unlink()

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_dir_path = Path(tmp_dir)
        tar_path     = tmp_dir_path / f'{dicom_study_name}.tar'
        zip_path     = tmp_dir_path / f'{dicom_study_name}.tar.gz'
        summary_path = tmp_dir_path / f'{dicom_study_name}.meta'
        log_path     = tmp_dir_path / f'{dicom_study_name}.log'

        log(env, "Copying the DICOM files into a new tar archive...")

        with tarfile.open(tar_path, 'w') as tar:
            for file_rel_path in iter_all_dir_files(args.source):
                file_path = args.source / file_rel_path
                file_tar_path = Path(args.source.name) / file_rel_path
                tar.add(file_path, arcname=file_tar_path)

        log(env, "Calculating the tar archive MD5 sum...")

        tar_md5_hash = loris_dicom_importer.text.compute_md5_hash_with_name(tar_path)

        log(env, "Zipping the tar archive... (may take a long time)")

        with open(tar_path, 'rb') as tar:
            # 6 is the default compression level of the `tar` command, Python's
            # default is 9, which is more compressed but also a lot slower.
            with gzip.open(zip_path, 'wb', compresslevel=6) as zip:
                shutil.copyfileobj(tar, zip)

        log(env, "Calculating the zipped tar archive MD5 sum...")

        zip_md5_hash = loris_dicom_importer.text.compute_md5_hash_with_name(zip_path)

        log(env, "Creating DICOM study import log...")

        dicom_import_log = make_dicom_study_import_log(args.source, dicom_archive_path, tar_md5_hash, zip_md5_hash)

        if args.verbose:
            dicom_import_log_string = write_dicom_study_import_log_to_string(dicom_import_log)
            log(env, f"The archive will be created with the following arguments:\n{dicom_import_log_string}")

        log(env, "Writing DICOM study summary file...")

        write_dicom_study_summary_to_file(dicom_summary, summary_path)

        log(env, "Writing DICOM study import log file...")

        write_dicom_study_import_log_to_file(dicom_import_log, log_path)

        log(env, 'Copying files into the final DICOM study archive...')

        with tarfile.open(dicom_archive_path, 'w') as tar:
            tar.add(zip_path,     zip_path.name)
            tar.add(summary_path, summary_path.name)
            tar.add(log_path,     log_path.name)

    log(env, "Calculating final DICOM study archive MD5 sum...")

    dicom_import_log.archive_md5_hash = loris_dicom_importer.text.compute_md5_hash_with_name(
        dicom_import_log.target_path
    )

    if not args.update:
        log(env, "Inserting the DICOM study in the LORIS database...")

        dicom_archive = insert_dicom_archive(env.db, dicom_summary, dicom_import_log, dicom_archive_rel_path)

    if args.update:
        log(env, "Updating the DICOM study in the LORIS database...")

        # Safe because we previously checked that the DICOM study is in LORIS.
        dicom_archive = cast(DbDicomArchive, dicom_archive)

        update_dicom_archive(env.db, dicom_archive, dicom_summary, dicom_import_log, dicom_archive_rel_path)

    if session is not None:
        log(env, "Updating the DICOM study session...")

        # Safe because we previously checked that the DICOM study is in LORIS.
        dicom_archive = cast(DbDicomArchive, dicom_archive)
        dicom_archive.session = session
        env.db.commit()

    log(env, "Success !")


if __name__ == '__main__':
    main()

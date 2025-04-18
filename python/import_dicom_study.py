#!/usr/bin/env python

import gzip
import os
import shutil
import tarfile
import tempfile
from typing import Any, cast

import lib.exitcode
import lib.import_dicom_study.text
from lib.config import get_dicom_archive_dir_path_config
from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.queries.dicom_archive import try_get_dicom_archive_with_study_uid
from lib.get_session_info import SessionConfigError
from lib.import_dicom_study.dicom_database import insert_dicom_archive, update_dicom_archive
from lib.import_dicom_study.import_log import (
    make_dicom_study_import_log,
    write_dicom_study_import_log_to_file,
    write_dicom_study_import_log_to_string,
)
from lib.import_dicom_study.summary_get import get_dicom_study_summary
from lib.import_dicom_study.summary_util import get_dicom_study_summary_session_info
from lib.import_dicom_study.summary_write import write_dicom_study_summary_to_file
from lib.logging import log, log_error_exit, log_warning
from lib.lorisgetopt import LorisGetOpt
from lib.make_env import make_env
from lib.util.fs import iter_all_dir_files


class Args:
    profile:   str
    source:    str
    insert:    bool
    update:    bool
    session:   bool
    overwrite: bool
    verbose:   bool

    def __init__(self, options_dict: dict[str, Any]):
        self.profile   = options_dict['profile']['value']
        self.source    = os.path.normpath(options_dict['source']['value'])
        self.overwrite = options_dict['overwrite']['value']
        self.insert    = options_dict['insert']['value']
        self.update    = options_dict['update']['value']
        self.session   = options_dict['session']['value']
        self.verbose   = options_dict['verbose']['value']


def main() -> None:
    usage = (
        "\n"
        "********************************************************************\n"
        " DICOM STUDY IMPORT SCRIPT\n"
        "********************************************************************\n"
        "This script reads a directory containing the DICOM files of a study, processes the\n"
        "directory into a structured and compressed archive, and inserts or uploads the study\n"
        "into the LORIS database.\n"
        "\n"
        "Usage: import_dicom_study.py -p <profile> -s <source_dir> ...\n"
        "\n"
        "Options: \n"
        "\t-p, --profile   : Name of the LORIS Python configuration file (usually\n"
        "\t                  'database_config.py')\n"
        "\t-s, --source    : Path of the source directory containing the DICOM files of the"
        "\t                  study.\n"
        "\t    --overwrite : Overwrite the DICOM archive file if it already exists.\n"
        "\t    --insert    : Insert the created DICOM archive in the database (requires the archive\n"
        "\t                  to not be already inserted).\n"
        "\t    --update    : Update the DICOM archive in the database (requires the archive to be\n"
        "\t                  already be inserted), generally used with '--overwrite'.\n"
        "\t    --session   : Associate the DICOM study with an existing session using the LORIS-MRI\n"
        "\t                  Python configuration.\n"
        "\t-v, --verbose   : If set, be verbose\n"
        "\n"
        "Required options: \n"
        "\t--profile\n"
        "\t--source\n"
        "\t--target\n"
    )

    # NOTE: Some options do not have short options but LorisGetOpt does not support that, so we
    # repeat the long names.
    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "source": {
            "value": None, "required": True,  "expect_arg": True, "short_opt": "s", "is_path": True,
        },
        "overwrite": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "overwrite", "is_path": False,
        },
        "insert": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "insert", "is_path": False,
        },
        "update": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "update", "is_path": False,
        },
        "session": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "session", "is_path": False,
        },
        "verbose": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "v", "is_path": False
        },
        "help": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "h", "is_path": False
        },
    }

    # Get the CLI arguments and connect to the database.

    loris_getopt_obj = LorisGetOpt(usage, options_dict, os.path.basename(__file__[:-3]))
    env = make_env(loris_getopt_obj)
    args = Args(loris_getopt_obj.options_dict)

    # Check arguments.

    if not os.path.isdir(args.source) or not os.access(args.source, os.R_OK):
        log_error_exit(
            env,
            "Argument '--source' must be a readable directory path.",
            lib.exitcode.INVALID_ARG,
        )

    if args.insert and args.update:
        log_error_exit(
            env,
            "Arguments '--insert' and '--update' cannot be used both at the same time.",
            lib.exitcode.INVALID_ARG,
        )

    if args.session and not (args.insert or args.update):
        log_error_exit(
            env,
            "Argument '--insert' or '--update' must be used when '--session' is used.",
            lib.exitcode.INVALID_ARG,
        )

    # Load configuration values.

    dicom_archive_dir_path = get_dicom_archive_dir_path_config(env)

    # Utility variables.

    dicom_study_name = os.path.basename(args.source)

    log(env, "Extracting DICOM information... (may take a long time)")

    dicom_summary = get_dicom_study_summary(args.source, args.verbose)

    log(env, "Checking if the DICOM study is already inserted in LORIS...")

    dicom_archive = try_get_dicom_archive_with_study_uid(env.db, dicom_summary.info.study_uid)

    if dicom_archive is not None:
        log(env, "Found the DICOM study in LORIS.")

        if args.insert:
            log_error_exit(
                env,
                (
                    "Cannot insert the DICOM study since it is already inserted in LORIS. Use"
                    " arguments '--update' and '--overwrite' to update the currently insrted DICOM"
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
                    "Cannot update the DICOM study since it is not already inserted in LORIS. Use"
                    " argument '--insert' to insert the DICOM study in LORIS."
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

        dicom_archive_rel_path = f'DCM_{dicom_study_name}.tar'
    else:
        log(env, f"Found DICOM scan date: {dicom_summary.info.scan_date}")

        scan_date_string = lib.import_dicom_study.text.write_date(dicom_summary.info.scan_date)
        dicom_archive_rel_path = os.path.join(
            str(dicom_summary.info.scan_date.year),
            f'DCM_{scan_date_string}_{dicom_study_name}.tar',
        )

        dicom_archive_year_dir_path = os.path.join(dicom_archive_dir_path, str(dicom_summary.info.scan_date.year))
        if not os.path.exists(dicom_archive_year_dir_path):
            log(env, f"Creating year directory '{dicom_archive_year_dir_path}'...")
            os.mkdir(dicom_archive_year_dir_path)

    dicom_archive_path = os.path.join(dicom_archive_dir_path, dicom_archive_rel_path)

    if os.path.exists(dicom_archive_path):
        if not args.overwrite:
            log_error_exit(
                env,
                f"File '{dicom_archive_path}' already exists. Use argument '--overwrite' to overwrite it",
            )

        log_warning(env, f"Overwriting file '{dicom_archive_path}'...")

        os.remove(dicom_archive_path)

    with tempfile.TemporaryDirectory() as tmp_dir_path:
        tar_path     = os.path.join(tmp_dir_path, f'{dicom_study_name}.tar')
        zip_path     = os.path.join(tmp_dir_path, f'{dicom_study_name}.tar.gz')
        summary_path = os.path.join(tmp_dir_path, f'{dicom_study_name}.meta')
        log_path     = os.path.join(tmp_dir_path, f'{dicom_study_name}.log')

        log(env, "Copying the DICOM files into a new tar archive...")

        with tarfile.open(tar_path, 'w') as tar:
            for file_rel_path in iter_all_dir_files(args.source):
                file_path = os.path.join(args.source, file_rel_path)
                file_tar_path = os.path.join(os.path.basename(args.source), file_rel_path)
                tar.add(file_path, arcname=file_tar_path)

        log(env, "Calculating the tar archive MD5 sum...")

        tar_md5_sum = lib.import_dicom_study.text.compute_md5_hash_with_name(tar_path)

        log(env, "Zipping the tar archive... (may take a long time)")

        with open(tar_path, 'rb') as tar:
            # 6 is the default compression level of the `tar` command, Python's
            # default is 9, which is more compressed but also a lot slower.
            with gzip.open(zip_path, 'wb', compresslevel=6) as zip:
                shutil.copyfileobj(tar, zip)

        log(env, "Calculating the zipped tar archive MD5 sum...")

        zip_md5_sum = lib.import_dicom_study.text.compute_md5_hash_with_name(zip_path)

        log(env, "Creating DICOM study import log...")

        dicom_import_log = make_dicom_study_import_log(args.source, dicom_archive_path, tar_md5_sum, zip_md5_sum)

        if args.verbose:
            dicom_import_log_string = write_dicom_study_import_log_to_string(dicom_import_log)
            log(env, f"The archive will be created with the following arguments:\n{dicom_import_log_string}")

        log(env, "Writing DICOM study summary file...")

        write_dicom_study_summary_to_file(dicom_summary, summary_path)

        log(env, "Writing DICOM study import log file...")

        write_dicom_study_import_log_to_file(dicom_import_log, log_path)

        log(env, 'Copying files into the final DICOM study archive...')

        with tarfile.open(dicom_archive_path, 'w') as tar:
            tar.add(zip_path,     os.path.basename(zip_path))
            tar.add(summary_path, os.path.basename(summary_path))
            tar.add(log_path,     os.path.basename(log_path))

    log(env, "Calculating final DICOM study archive MD5 sum...")

    dicom_import_log.archive_md5_sum = lib.import_dicom_study.text.compute_md5_hash_with_name(
        dicom_import_log.target_path
    )

    if args.insert:
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

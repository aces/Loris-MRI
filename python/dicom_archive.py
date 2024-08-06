#!/usr/bin/env python

from typing import Any, cast
import gzip
import os
import shutil
import sys
import tarfile

import lib.dicom.dicom_database
import lib.dicom.dicom_log
import lib.dicom.summary_make
import lib.dicom.summary_write
import lib.dicom.text
import lib.exitcode
from lib.lorisgetopt import LorisGetOpt


def print_error_exit(message: str, code: int):
    print(f'ERROR: {message}', file=sys.stderr)
    sys.exit(code)


def print_warning(message: str):
    print(f'WARNING: {message}', file=sys.stderr)


def main():
    def check_create_file(path: str):
        if os.path.exists(path):
            if arg_overwrite:
                print_warning(f'Overwriting \'{path}\'')
            else:
                print_error_exit(
                    (
                        f'File or directory \'{path}\' already exists. '
                        'Use option \'--overwrite\' to overwrite it.'
                    ),
                    lib.exitcode.TARGET_EXISTS_NO_CLOBBER,
                )


    usage = (
        "\n"

        "********************************************************************\n"
        " DICOM ARCHIVING SCRIPT\n"
        "********************************************************************\n"
        "The program reads a DICOM directory, processes it into a structured and "
        "compressed archive, and insert it or upload it to the LORIS database."

        "usage  : dicom_archive.py -p <profile> -s <source_dir> -t <target_dir> ...\n\n"

        "options: \n"
        "\t-p, --profile   : Name of the python database config file in dicom-archive/.loris_mri\n"
        "\t-s, --source    : Source directory containing the DICOM files to archive\n"
        "\t-t, --target    : Directory in which to place the resulting DICOM archive\n"
        "\t    --today     : Use today's date as the scan date instead of the DICOM scan date\n"
        "\t    --year      : Create the archive in a year subdirectory (example: 2024/DCM_2024-08-27_FooBar.tar)s\n"
        "\t    --overwrite : Overwrite the DICOM archive file if it already exists\n"
        "\t    --db-insert : Insert the created DICOM archive in the database (requires the archive\n"
        "\t                  to not be already inserted)\n"
        "\t    --db-update : Update the DICOM archive in the database (requires the archive to be\n"
        "\t                  already be inserted), generally used with --overwrite"
        "\t-v, --verbose   : If set, be verbose\n\n"

        "required options are: \n"
        "\t--profile\n"
        "\t--source\n"
        "\t--target\n\n"
    )

    # NOTE: Some options do not have short options but LorisGetOpt does not support that, so we
    # repeat the long names.
    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "source": {
            "value": None,  "required": True,  "expect_arg": True, "short_opt": "s", "is_path": True,
        },
        "target": {
            "value": None,  "required": True,  "expect_arg": True, "short_opt": "t", "is_path": True,
        },
        "today": {
            "value": False,  "required": False,  "expect_arg": False, "short_opt": "today", "is_path": False,
        },
        "year": {
            "value": False,  "required": False,  "expect_arg": False, "short_opt": "year", "is_path": False,
        },
        "overwrite": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "overwrite", "is_path": False,
        },
        "db-insert": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "db-insert", "is_path": False,
        },
        "db-update": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "db-update", "is_path": False,
        },
        "verbose": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "v", "is_path": False
        },
        "help": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "h", "is_path": False
        },
    }

    # get the options provided by the user
    loris_getopt_obj = LorisGetOpt(usage, options_dict, os.path.basename(__file__[:-3]))

    # Typed arguments

    arg_profile:   str | None = loris_getopt_obj.options_dict['profile']['value']
    arg_source:    str        = loris_getopt_obj.options_dict['source']['value']
    arg_target:    str        = loris_getopt_obj.options_dict['target']['value']
    arg_today:     bool       = loris_getopt_obj.options_dict['today']['value']
    arg_year:      bool       = loris_getopt_obj.options_dict['year']['value']
    arg_overwrite: bool       = loris_getopt_obj.options_dict['overwrite']['value']
    arg_db_insert: bool       = loris_getopt_obj.options_dict['db-insert']['value']
    arg_db_update: bool       = loris_getopt_obj.options_dict['db-update']['value']
    arg_verbose:   bool       = loris_getopt_obj.options_dict['verbose']['value']

    db = loris_getopt_obj.db

    # Check arguments

    if arg_db_insert and arg_db_update:
        print_error_exit(
            'Arguments \'--db-insert\' and \'--db-update\' must not be set both at the same time.',
            lib.exitcode.INVALID_ARG,
        )

    if (arg_db_insert or arg_db_update) and not arg_profile:
        print_error_exit(
            'Argument \'--profile\' must be set when a \'--db-*\' argument is set.',
            lib.exitcode.INVALID_ARG,
        )

    if not os.path.isdir(arg_source) or not os.access(arg_source, os.R_OK):
        print_error_exit(
            'Argument \'--source\' must be a readable directory path.',
            lib.exitcode.INVALID_ARG,
        )

    if not os.path.isdir(arg_target) or not os.access(arg_target, os.W_OK):
        print_error_exit(
            'Argument \'--target\' must be a writable directory path.',
            lib.exitcode.INVALID_ARG,
        )

    # Check paths

    while arg_source.endswith('/'):
        arg_source = arg_source[:-1]

    base_name = os.path.basename(arg_source)

    tar_path     = f'{arg_target}/{base_name}.tar'
    zip_path     = f'{arg_target}/{base_name}.tar.gz'
    summary_path = f'{arg_target}/{base_name}.meta'
    log_path     = f'{arg_target}/{base_name}.log'

    check_create_file(tar_path)
    check_create_file(zip_path)
    check_create_file(summary_path)
    check_create_file(log_path)

    print('Extracting DICOM information (may take a long time)')

    summary = lib.dicom.summary_make.make(arg_source, arg_verbose)

    print('Checking database presence')

    db_archive = lib.dicom.dicom_database.get_archive_with_study_uid(db, summary.info.study_uid)

    if arg_db_insert and db_archive is not None:
        print_error_exit(
            (
                f'Study \'{summary.info.study_uid}\' is already inserted in the database\n'
                'Previous archiving log:\n'
                f'{db_archive[1]}'
            ),
            lib.exitcode.INSERT_FAILURE,
        )

    if arg_db_update and db_archive is None:
        print_error_exit(
            f'No study \'{summary.info.study_uid}\' found in the database',
            lib.exitcode.UPDATE_FAILURE,
        )

    print('Copying into DICOM tar')

    with tarfile.open(tar_path, 'w') as tar:
        for file in os.listdir(arg_source):
            tar.add(arg_source + '/' + file)

    print('Calculating DICOM tar MD5 sum')

    tarball_md5_sum = lib.dicom.text.make_hash(tar_path, True)

    print('Zipping DICOM tar (may take a long time)')

    with open(tar_path, 'rb') as tar:
        with gzip.open(zip_path, 'wb') as zip:
            shutil.copyfileobj(tar, zip)

    print('Calculating DICOM zip MD5 sum')

    zipball_md5_sum = lib.dicom.text.make_hash(zip_path, True)

    print('Getting DICOM scan date')

    if not arg_today and summary.info.scan_date is None:
        print_warning((
            'No scan date was found in the DICOMs, '
            'consider using argument \'--today\' to use today\'s date as the scan date.'
        ))

    if arg_year and summary.info.scan_date is None:
        print_warning((
            'Argument \'--year\' was provided but no scan date was found in the DICOMs, '
            'the argument will be ignored.'
        ))

    if arg_year and summary.info.scan_date is not None:
        dir_path = f'{arg_target}/{summary.info.scan_date.year}'
        if not os.path.exists(dir_path):
            print(f'Creating directory \'{dir_path}\'')
            os.mkdir(dir_path)
        elif not os.path.isdir(dir_path) or not os.access(dir_path, os.W_OK):
            print_error_exit(
                f'Path \'{dir_path}\' exists but is not a writable directory.',
                lib.exitcode.CREATE_DIR_FAILURE,
            )
    else:
        dir_path = arg_target

    if summary.info.scan_date is not None:
        scan_date_string = lib.dicom.text.write_date(summary.info.scan_date)
        archive_path = f'{dir_path}/DCM_{scan_date_string}_{base_name}.tar'
    else:
        archive_path = f'{dir_path}/DCM_{base_name}.tar'

    check_create_file(archive_path)

    log = lib.dicom.dicom_log.make(arg_source, archive_path, tarball_md5_sum, zipball_md5_sum)

    if arg_verbose:
        print('The archive will be created with the following arguments:')
        print(lib.dicom.dicom_log.write_to_string(log))

    print('Writing summary file')

    lib.dicom.summary_write.write_to_file(summary_path, summary)

    print('Writing log file')

    lib.dicom.dicom_log.write_to_file(log_path, log)

    print('Copying into DICOM archive')

    with tarfile.open(archive_path, 'w') as tar:
        tar.add(zip_path,     os.path.basename(zip_path))
        tar.add(summary_path, os.path.basename(summary_path))
        tar.add(log_path,     os.path.basename(log_path))

    print('Removing temporary files')

    os.remove(tar_path)
    os.remove(zip_path)
    os.remove(summary_path)
    os.remove(log_path)

    print('Calculating DICOM tar MD5 sum')

    log.archive_md5_sum = lib.dicom.text.make_hash(log.target_path, True)

    if arg_db_insert:
        lib.dicom.dicom_database.insert(db, log, summary)

    if arg_db_update:
        db_archive = cast(tuple[Any, Any], db_archive)
        lib.dicom.dicom_database.update(db, db_archive[0], log, summary)

    print('Success')


if __name__ == "__main__":
    main()

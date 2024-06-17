#!/usr/bin/env python

from datetime import date
from typing import Any, cast
import argparse
import gzip
import os
import shutil
import sys
import tarfile

from lib.database import Database
import lib.dicom.dicom_database
import lib.dicom.dicom_log
import lib.dicom.summary_make
import lib.dicom.summary_write
import lib.dicom.text
import lib.exitcode


def print_error_exit(message: str, code: int):
    print(f'ERROR: {message}', file=sys.stderr)
    sys.exit(code)


def print_warning(message: str):
    print(f'WARNING: {message}', file=sys.stderr)


def check_create_file(path: str):
    if os.path.exists(path):
        if overwrite:
            print_warning(f'Overwriting \'{path}\'')
        else:
            print_error_exit(
                (
                    f'File or directory \'{path}\' already exists. '
                    'Use option \'--overwrite\' to overwrite it.'
                ),
                lib.exitcode.TARGET_EXISTS_NO_CLOBBER,
            )


# Modified version of 'lorisgetopt.load_config_file'.
# We use argparse to parse the command line options in this script,
# but still use this function to configure the database.
def load_config_file(profile_path: str):
    """
    Load the config file based on the value provided by the option '--profile' when
    running the script. If the config file cannot be loaded, the script will exit
    with a proper error message.
    """

    if "LORIS_CONFIG" not in os.environ.keys():
        print_error_exit(
            'Environment variable \'LORIS_CONFIG\' not set',
            lib.exitcode.INVALID_ENVIRONMENT_VAR,
        )

    config_file = os.path.join(os.environ["LORIS_CONFIG"], ".loris_mri", profile_path)

    if not config_file.endswith(".py"):
        print_error_exit(
            (
                f'\'{config_file}\' does not appear to be the python configuration file.'
                f' Try using \'database_config.py\' instead.'
            ),
            lib.exitcode.INVALID_ARG,
        )

    if not os.path.isfile(config_file):
        print_error_exit(
            f'\'{profile_path}\' does not exist in \'{os.environ["LORIS_CONFIG"]}\'.',
            lib.exitcode.INVALID_PATH,
        )

    sys.path.append(os.path.dirname(config_file))
    return __import__(os.path.basename(config_file[:-3]))


parser = argparse.ArgumentParser(description=(
        'Read a DICOM directory, process it into a structured and compressed archive, '
        'and insert it or upload it to the LORIS database.'
    ))

parser.add_argument(
    '--profile',
    action='store',
    default=None,
    help='The database profile file (usually \'database_config.py\')')

parser.add_argument(
    '--verbose',
    action='store_true',
    help='Set the script to be verbose')

parser.add_argument(
    '--today',
    action='store_true',
    help='Use today\'s date for the archive name instead of using the scan date')

parser.add_argument(
    '--year',
    action='store_true',
    help='Create the archive in a year subdirectory (example: 2024/DCM_2024-08-27_FooBar.tar)')

parser.add_argument(
    '--overwrite',
    action='store_true',
    help='Overwrite the DICOM archive file if it already exists')

parser.add_argument(
    '--db-insert',
    action='store_true',
    help=(
        'Insert the created DICOM archive in the database (requires the archive '
        'to not be already inserted)'))

parser.add_argument(
    '--db-update',
    action='store_true',
    help=(
        'Update the DICOM archive in the database, which requires the archive to be '
        'already be inserted), generally used with \'--overwrite\''))

parser.add_argument(
    'source',
    help='The source DICOM directory')

parser.add_argument(
    'target',
    help='The target directory for the DICOM archive')

args = parser.parse_args()

# Typed arguments

profile:   str | None = args.profile
source:    str        = args.source
target:    str        = args.target
verbose:   bool       = args.verbose
today:     bool       = args.today
year:      bool       = args.year
overwrite: bool       = args.overwrite
db_insert: bool       = args.db_insert
db_update: bool       = args.db_update

# Check arguments

if db_insert and db_update:
    print_error_exit(
        'Arguments \'--db-insert\' and \'--db-update\' must not be set both at the same time.',
        lib.exitcode.INVALID_ARG,
    )

if (db_insert or db_update) and not profile:
    print_error_exit(
        'Argument \'--profile\' must be set when a \'--db-*\' argument is set.',
        lib.exitcode.INVALID_ARG,
    )

if not os.path.isdir(source) or not os.access(source, os.R_OK):
    print_error_exit(
        'Argument \'--source\' must be a readable directory path.',
        lib.exitcode.INVALID_ARG,
    )

if not os.path.isdir(target) or not os.access(target, os.W_OK):
    print_error_exit(
        'Argument \'--target\' must be a writable directory path.',
        lib.exitcode.INVALID_ARG,
    )

# Connect to database (if needed)

db = None
if profile is not None:
    db = Database(load_config_file(profile).mysql, False)
    db.connect()

# Check paths

while source.endswith('/'):
    source = source[:-1]

base_name = os.path.basename(source)

tar_path     = f'{target}/{base_name}.tar'
zip_path     = f'{target}/{base_name}.tar.gz'
summary_path = f'{target}/{base_name}.meta'
log_path     = f'{target}/{base_name}.log'

check_create_file(tar_path)
check_create_file(zip_path)
check_create_file(summary_path)
check_create_file(log_path)

print('Extracting DICOM information (may take a long time)')

summary = lib.dicom.summary_make.make(source, verbose)

if db is not None:
    print('Checking database presence')

    archive = lib.dicom.dicom_database.get_archive_with_study_uid(db, summary.info.study_uid)

    if db_insert and archive is not None:
        print_error_exit(
            (
                f'Study \'{summary.info.study_uid}\' is already inserted in the database\n'
                'Previous archiving log:\n'
                f'{archive[1]}'
            ),
            lib.exitcode.INSERT_FAILURE,
        )

    if db_update and archive is None:
        print_error_exit(
            f'No study \'{summary.info.study_uid}\' found in the database',
            lib.exitcode.UPDATE_FAILURE,
        )
else:
    # Placeholder for type checker
    archive = None

print('Copying into DICOM tar')

with tarfile.open(tar_path, 'w') as tar:
    for file in os.listdir(source):
        tar.add(source + '/' + file)

print('Calculating DICOM tar MD5 sum')

tarball_md5_sum = lib.dicom.text.make_hash(tar_path, True)

print('Zipping DICOM tar (may take a long time)')

with open(tar_path, 'rb') as tar:
    with gzip.open(zip_path, 'wb') as zip:
        shutil.copyfileobj(tar, zip)

print('Calculating DICOM zip MD5 sum')

zipball_md5_sum = lib.dicom.text.make_hash(zip_path, True)

print('Getting DICOM scan date')

if not today and summary.info.scan_date is None:
    print_warning((
        'No scan date found for this DICOM archive, '
        'consider using argument \'--today\' to use today\'s date instead.'
    ))

scan_date = date.today() if today else summary.info.scan_date

if year:
    if not scan_date:
        print_error_exit(
            'Cannot use year directory with no date found for this DICOM archive.',
            lib.exitcode.CREATE_DIR_FAILURE,
        )

    scan_date = cast(date, scan_date)

    dir_path = f'{target}/{scan_date.year}'
    if not os.path.exists(dir_path):
        print(f'Creating directory \'{dir_path}\'')
        os.mkdir(dir_path)
    elif not os.path.isdir(dir_path) or not os.access(dir_path, os.W_OK):
        print_error_exit(
            f'Path \'{dir_path}\' exists but is not a writable directory.',
            lib.exitcode.CREATE_DIR_FAILURE,
        )
else:
    dir_path = target

scan_date_string = lib.dicom.text.write_date_none(scan_date) or ''
archive_path = f'{dir_path}/DCM_{scan_date_string}_{base_name}.tar'

check_create_file(archive_path)

log = lib.dicom.dicom_log.make(source, archive_path, tarball_md5_sum, zipball_md5_sum)

if verbose:
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

if db_insert:
    # `db` cannot be `None` here.
    db = cast(Database, db)
    lib.dicom.dicom_database.insert(db, log, summary)

if db_update:
    # `db` and `archive` cannot be `None` here.
    db = cast(Database, db)
    archive = cast(tuple[Any, Any], archive)
    lib.dicom.dicom_database.update(db, archive[0], log, summary)

print('Success')

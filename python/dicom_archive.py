#!/usr/bin/env python

from typing import Any, cast
import gzip
import os
import shutil
import sys
import tarfile

from lib.db.connect import connect_to_db
import lib.dicom.dicom_database
import lib.dicom.dicom_log
import lib.dicom.summary_make
import lib.dicom.summary_write
import lib.dicom.text
import lib.exitcode
from lib.lorisgetopt import LorisGetOpt
import lib.database
from lib.db.model.dicom_archive import DbDicomArchive
from lib.db.query.dicom_archive import try_get_dicom_archive_with_study_uid
from lib.db.query.mri_upload import try_get_mri_upload_with_id
from lib.db.query.session import try_get_session_with_cand_id_visit_label


def print_error_exit(message: str, code: int):
    print(f'ERROR: {message}', file=sys.stderr)
    sys.exit(code)


def print_warning(message: str):
    print(f'WARNING: {message}', file=sys.stderr)


class Args:
    profile:   str
    source:    str
    target:    str
    today:     bool
    year:      bool
    overwrite: bool
    insert:    bool
    update:    bool
    upload:    int | None
    session:   bool
    verbose:   bool

    def __init__(self, options_dict: dict[str, Any]):
        self.profile   = options_dict['profile']['value']
        self.source    = options_dict['source']['value']
        self.target    = options_dict['target']['value']
        self.today     = options_dict['today']['value']
        self.year      = options_dict['year']['value']
        self.overwrite = options_dict['overwrite']['value']
        self.insert    = options_dict['insert']['value']
        self.update    = options_dict['update']['value']
        self.upload    = options_dict['upload']['value']
        self.session   = options_dict['session']['value']
        self.verbose   = options_dict['verbose']['value']


def check_create_file(args: Args, path: str):
    if os.path.exists(path):
        if args.overwrite:
            print_warning(f'Overwriting \'{path}\'')
        else:
            print_error_exit(
                (
                    f'File or directory \'{path}\' already exists. '
                    'Use option \'--overwrite\' to overwrite it.'
                ),
                lib.exitcode.TARGET_EXISTS_NO_CLOBBER,
            )


def main():
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
        "\t    --insert    : Insert the created DICOM archive in the database (requires the archive\n"
        "\t                  to not be already inserted)\n"
        "\t    --update    : Update the DICOM archive in the database (requires the archive to be\n"
        "\t                  already be inserted), generally used with --overwrite"
        "\t    --upload    : Associate the DICOM archive with an existing MRI upload in the database, which is\n"
        "                    updated accordingly"
        "\t    --session   : Determine the session for the DICOM archive using the LORIS configuration, and associate\n"
        "                    them accordingly"
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
            "value": None, "required": True,  "expect_arg": True, "short_opt": "s", "is_path": True,
        },
        "target": {
            "value": None, "required": True,  "expect_arg": True, "short_opt": "t", "is_path": True,
        },
        "today": {
            "value": False, "required": False,  "expect_arg": False, "short_opt": "today", "is_path": False,
        },
        "year": {
            "value": False, "required": False,  "expect_arg": False, "short_opt": "year", "is_path": False,
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
        "upload": {
            "value": True, "required": False, "expect_arg": False, "short_opt": "upload", "is_path": False,
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

    # Get the CLI arguments and connect to the database

    loris_getopt_obj = LorisGetOpt(usage, options_dict, os.path.basename(__file__[:-3]))
    args = Args(loris_getopt_obj.options_dict)

    config = cast(Any, loris_getopt_obj.config_info).mysql
    db = connect_to_db(config.mysql)
    old_db = lib.database.Database(config.mysql, args.verbose)
    get_subject_ids = None
    try:
        get_subject_ids = config.get_subject_ids
    except AttributeError:
        print_error_exit(
            'Config file does not contain a `get_subject_ids` function.',
            lib.exitcode.BAD_CONFIG_SETTING,
        )

    # Check arguments

    if args.insert and args.update:
        print_error_exit(
            'Arguments \'--insert\' and \'--update\' must not be set both at the same time.',
            lib.exitcode.INVALID_ARG,
        )

    if not os.path.isdir(args.source) or not os.access(args.source, os.R_OK):
        print_error_exit(
            'Argument \'--source\' must be a readable directory path.',
            lib.exitcode.INVALID_ARG,
        )

    if not os.path.isdir(args.target) or not os.access(args.target, os.W_OK):
        print_error_exit(
            'Argument \'--target\' must be a writable directory path.',
            lib.exitcode.INVALID_ARG,
        )

    if (args.session or args.upload is not None) and not (args.insert or args.update):
        print_error_exit(
            'Arguments \'--db-insert\' or \'--db-update\' must be set when \'--db-session\' or \'--db-upload\' is set.',
            lib.exitcode.INVALID_ARG,
        )

    # Check paths

    base_name = os.path.basename(args.source)

    tar_path     = f'{args.target}/{base_name}.tar'
    zip_path     = f'{args.target}/{base_name}.tar.gz'
    summary_path = f'{args.target}/{base_name}.meta'
    log_path     = f'{args.target}/{base_name}.log'

    check_create_file(args, tar_path)
    check_create_file(args, zip_path)
    check_create_file(args, summary_path)
    check_create_file(args, log_path)

    # Check MRI upload

    mri_upload = None
    if args.upload is not None:
        mri_upload = try_get_mri_upload_with_id(db, args.upload)
        if mri_upload is None:
            print_error_exit(
                f'No MRI upload found in the database with id {args.upload}.',
                lib.exitcode.UPDATE_FAILURE,
            )

    print('Extracting DICOM information (may take a long time)')

    summary = lib.dicom.summary_make.make(args.source, args.verbose)

    print('Checking database presence')

    dicom_archive = try_get_dicom_archive_with_study_uid(db, summary.info.study_uid)

    if args.insert and dicom_archive is not None:
        print_error_exit(
            (
                f'Study \'{summary.info.study_uid}\' is already inserted in the database\n'
                'Previous archiving log:\n'
                f'{dicom_archive.create_info}'
            ),
            lib.exitcode.INSERT_FAILURE,
        )

    if args.update and dicom_archive is None:
        print_error_exit(
            f'No study \'{summary.info.study_uid}\' found in the database',
            lib.exitcode.UPDATE_FAILURE,
        )

    session = None
    if args.session:
        get_subject_ids = cast(Any, get_subject_ids)

        print('Determine session from configuration')

        ids = get_subject_ids(old_db, summary.info.patient.name)
        cand_id     = ids['CandID']
        visit_label = ids['visitLabel']
        session = try_get_session_with_cand_id_visit_label(db, cand_id, visit_label)

        if session is None:
            print_error_exit(
                (
                    f'No session found in the database for patient name \'{summary.info.patient.name}\' '
                    f'and visit label \'{visit_label}\'.'
                ),
                lib.exitcode.GET_SESSION_ID_FAILURE,
            )

    print('Copying into DICOM tar')

    with tarfile.open(tar_path, 'w') as tar:
        for file in os.listdir(args.source):
            tar.add(args.source + '/' + file)

    print('Calculating DICOM tar MD5 sum')

    tarball_md5_sum = lib.dicom.text.make_hash(tar_path, True)

    print('Zipping DICOM tar (may take a long time)')

    with open(tar_path, 'rb') as tar:
        # 6 is the default compression level of the tar command, Python's
        # default is 9, which is more powerful but also too slow.
        with gzip.open(zip_path, 'wb', compresslevel=6) as zip:
            shutil.copyfileobj(tar, zip)

    print('Calculating DICOM zip MD5 sum')

    zipball_md5_sum = lib.dicom.text.make_hash(zip_path, True)

    print('Getting DICOM scan date')

    if not args.today and summary.info.scan_date is None:
        print_warning((
            'No scan date was found in the DICOMs, '
            'consider using argument \'--today\' to use today\'s date as the scan date.'
        ))

    if args.year and summary.info.scan_date is None:
        print_warning((
            'Argument \'--year\' was provided but no scan date was found in the DICOMs, '
            'the argument will be ignored.'
        ))

    if args.year and summary.info.scan_date is not None:
        dir_path = f'{args.target}/{summary.info.scan_date.year}'
        if not os.path.exists(dir_path):
            print(f'Creating directory \'{dir_path}\'')
            os.mkdir(dir_path)
        elif not os.path.isdir(dir_path) or not os.access(dir_path, os.W_OK):
            print_error_exit(
                f'Path \'{dir_path}\' exists but is not a writable directory.',
                lib.exitcode.CREATE_DIR_FAILURE,
            )
    else:
        dir_path = args.target

    if summary.info.scan_date is not None:
        scan_date_string = lib.dicom.text.write_date(summary.info.scan_date)
        archive_path = f'{dir_path}/DCM_{scan_date_string}_{base_name}.tar'
    else:
        archive_path = f'{dir_path}/DCM_{base_name}.tar'

    check_create_file(args, archive_path)

    log = lib.dicom.dicom_log.make(args.source, archive_path, tarball_md5_sum, zipball_md5_sum)

    if args.verbose:
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

    if args.insert:
        lib.dicom.dicom_database.insert(db, log, summary)

    if args.update:
        # Safe because we checked previously that the DICOM archive is not `None`
        dicom_archive = cast(DbDicomArchive, dicom_archive)
        lib.dicom.dicom_database.update(db, dicom_archive, log, summary)

    if mri_upload is not None:
        print('Updating MRI upload in the database')
        dicom_archive = cast(DbDicomArchive, dicom_archive)
        dicom_archive.upload = mri_upload

    if session is not None:
        dicom_archive = cast(DbDicomArchive, dicom_archive)
        dicom_archive.session = session

        if mri_upload is not None:
            mri_upload.session = session

    print('Success')


if __name__ == "__main__":
    main()

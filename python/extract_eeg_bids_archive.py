#!/usr/bin/env python

"""Script that extract EEG archives"""

import os
import sys
import re
from lib.lorisgetopt import LorisGetOpt
from lib.imaging_io import ImagingIO
from lib.database import Database
from lib.database_lib.config import Config
from lib.exitcode import SUCCESS, MISSING_FILES, BAD_CONFIG_SETTING, COPY_FAILURE
from lib.log import Log

__license__ = "GPLv3"

sys.path.append('/home/user/python')


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " EXTRACT EEG ARCHIVES\n"
        "********************************************************************\n"
        "The program gets an archive associated with an upload ID, extract it and push its content "
        "to EEGS3DataPath, an Amazon S3 bucket or {dataDirBasepath}/assembly_bids.\n\n"

        "usage  : extract_eeg_bids_archive.py -p <profile> -u <upload_id> ...\n\n"

        "options: \n"
        "\t-p, --profile            : Name of the python database config file in dicom-archive/.loris_mri\n"
        "\t-u, --upload_id          : ID of the upload (from electrophysiology_uploader) of the EEG archive\n"
        "\t-v, --verbose            : If set, be verbose\n\n"

        "required options are: \n"
        "\t--profile\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "upload_id": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "u", "is_path": False
        },
        "verbose": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "v", "is_path": False
        },
        "help": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "h", "is_path": False
        },
    }

    script_name = os.path.basename(__file__[:-3])
    # get the options provided by the user
    loris_getopt_obj = LorisGetOpt(usage, options_dict, script_name)
    verbose = loris_getopt_obj.options_dict['verbose']['value']
    upload_id = loris_getopt_obj.options_dict['upload_id']['value']

    s3_obj = loris_getopt_obj.s3_obj

    # ---------------------------------------------------------------------------------------------
    # Establish database connection
    # ---------------------------------------------------------------------------------------------
    config_file = loris_getopt_obj.config_info
    db = Database(config_file.mysql, verbose)
    db.connect()

    # ---------------------------------------------------------------------------------------------
    # Load the Config database class
    # ---------------------------------------------------------------------------------------------
    config_db_obj = Config(db, verbose)

    # ---------------------------------------------------------------------------------------------
    # Get tmp dir from loris_getopt object
    # and create the log object (their basename being the name of the script run)
    # ---------------------------------------------------------------------------------------------
    tmp_dir = loris_getopt_obj.tmp_dir
    data_dir = config_db_obj.get_config("dataDirBasepath")
    log_obj = Log(
        db,
        data_dir,
        script_name,
        os.path.basename(tmp_dir),
        loris_getopt_obj.options_dict,
        verbose
    )
    imaging_io_obj = ImagingIO(log_obj, verbose)

    # ---------------------------------------------------------------------------------------------
    # Grep config settings from the Config module
    # ---------------------------------------------------------------------------------------------
    eeg_incoming_dir = config_db_obj.get_config("EEGUploadIncomingPath")

    if upload_id:
        # ---------------------------------------------------------------------------------------------
        # Get all EEG upload with status = Not Started
        # ---------------------------------------------------------------------------------------------
        query = "SELECT UploadLocation" \
                " FROM electrophysiology_uploader" \
                " WHERE Status = 'Not Started'" \
                " AND UploadID = %s"

        eeg_archives_list = db.pselect(query, (upload_id,))
    else:
        # ---------------------------------------------------------------------------------------------
        # Get all EEG upload with status = Not Started
        # ---------------------------------------------------------------------------------------------
        query = "SELECT UploadLocation" \
                " FROM electrophysiology_uploader" \
                " WHERE Status = 'Not Started'" \

        eeg_archives_list = db.pselect(query, ())

    if not eeg_archives_list:
        print('No new EEG upload to extract.')
        sys.exit(SUCCESS)

    # ---------------------------------------------------------------------------------------------
    # Check if the upload already exist (re-upload)
    # ---------------------------------------------------------------------------------------------

    for eeg_archive_file in eeg_archives_list:
        eeg_archive_filename = eeg_archive_file['UploadLocation']
        eeg_archive_path = os.path.join(eeg_incoming_dir, eeg_archive_filename)
        error = False

        if s3_obj and eeg_incoming_dir.startswith('s3://'):
            eeg_archive_local_path = os.path.join(tmp_dir, eeg_archive_filename)
            try:
                s3_obj.download_file(eeg_archive_path, eeg_archive_local_path)
            except Exception as err:
                imaging_io_obj.log_info(
                    f"{eeg_archive_path} could not be downloaded from S3 bucket. Error was\n{err}",
                    is_error=True,
                    is_verbose=False,
                )
                error = True
            else:
                eeg_archive_path = eeg_archive_local_path

        elif eeg_incoming_dir.startswith('s3://'):
            imaging_io_obj.log_error_and_exit(
                f"{eeg_incoming_dir} is a S3 path but S3 server connection could not be established.",
                BAD_CONFIG_SETTING
            )

        if not error:
            try:
                # Uncompress archive in tmp location
                eeg_collection_path = imaging_io_obj.extract_archive(eeg_archive_path, 'EEG', tmp_dir)
            except Exception as err:
                imaging_io_obj.log_info(
                    f"Could not extract {eeg_archive_path} - {format(err)}",
                    is_error=True,
                    is_verbose=False,
                )
                error = True

        if not error:
            tmp_eeg_session_path = None
            eeg_session_rel_path = None
            modalities = None
            for (root, dirs, files) in os.walk(eeg_collection_path):
                if os.path.basename(os.path.normpath(root)).startswith('ses-'):
                    tmp_eeg_session_path = root
                    modalities = dirs

                    eeg_session_rel_path_re = re.search(r'sub-.+$', root)
                    if eeg_session_rel_path_re:
                        eeg_session_rel_path = eeg_session_rel_path_re.group()
                    else:
                        imaging_io_obj.log_info(
                            f"Could not find a subject folder in the BIDS structure for {eeg_archive_file}.",
                            is_error=True,
                            is_verbose=False,
                        )
                        error = True
                        break

        if not error and not tmp_eeg_session_path:
            imaging_io_obj.log_info(
                "Could not find a session folder in the bids structure for .",
                is_error=True,
                is_verbose=False,
            )
            error = True

        if not error:
            for modality in modalities:
                tmp_eeg_modality_path = os.path.join(tmp_eeg_session_path, modality)
                s3_data_dir = config_db_obj.get_config("EEGS3DataPath")

                if s3_obj and s3_data_dir and s3_data_dir.startswith('s3://'):
                    s3_data_eeg_modality_path = os.path.join(s3_data_dir, eeg_session_rel_path, modality)

                    try:
                        """
                        If the suject/session/modality BIDS data already exists
                        on the destination folder, delete it first
                        before copying the data
                        """
                        s3_obj.delete_file(s3_data_eeg_modality_path)

                        # Move folder in S3 bucket
                        s3_obj.upload_dir(tmp_eeg_modality_path, s3_data_eeg_modality_path)
                    except Exception as err:
                        imaging_io_obj.log_info(
                            f"{tmp_eeg_modality_path} could not be uploaded to the S3 bucket. Error was\n{err}",
                            is_error=True,
                            is_verbose=False,
                        )
                        error = True
                else:
                    data_eeg_modality_path = os.path.join(data_dir, 'assembly_bids', eeg_session_rel_path, modality)

                    """
                    If the suject/session/modality BIDS data already exists
                    on the destination folder, delete if first
                    copying the data
                    """
                    imaging_io_obj.remove_dir(data_eeg_modality_path)
                    imaging_io_obj.copy_file(tmp_eeg_modality_path, data_eeg_modality_path)

        # Delete tmp location
        imaging_io_obj.remove_dir(tmp_dir)

        if not error:
            # Set Status = Extracted
            db.update(
                "UPDATE electrophysiology_uploader SET Status = 'Extracted' WHERE UploadLocation = %s",
                (eeg_archive_filename,)
            )
        else:
            # Set Status = 'Failed Extraction'
            db.update(
                "UPDATE electrophysiology_uploader SET Status = 'Failed Extraction' WHERE UploadLocation = %s",
                (eeg_archive_filename,)
            )


if __name__ == "__main__":
    main()

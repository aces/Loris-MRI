#!/usr/bin/env python

"""Script that extract EEG archives"""

import os
import re
import sys

import lib.utilities as utilities
from lib.database import Database
from lib.database_lib.config import Config
from lib.exitcode import BAD_CONFIG_SETTING, SUCCESS
from lib.logging import log, log_error, log_error_exit, log_warning
from lib.lorisgetopt import LorisGetOpt
from lib.make_env import make_env
from lib.util.fs import copy_file, extract_archive, remove_directory

sys.path.append('/home/user/python')


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " EXTRACT EEG ARCHIVES\n"
        "********************************************************************\n"
        "The program gets an archive associated with an upload ID, extract it and push its content "
        "to EEGS3DataPath, an Amazon S3 bucket or EEGAssemblyBIDS.\n\n"

        "usage  : extract_eeg_bids_archive.py -p <profile> -u <upload_id> ...\n\n"

        "options: \n"
        "\t-p, --profile            : Name of the python database config file in config\n"
        "\t-u, --upload_id          : ID of the upload (from electrophysiology_uploader) of the EEG archive\n"
        "\t-v, --verbose            : If set, be verbose\n\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "p", "is_path": False
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
    env = make_env(loris_getopt_obj)

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
        log(env, "No new EEG upload to extract.")
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
                log_error(env, f"{eeg_archive_path} could not be downloaded from S3 bucket. Error was\n{err}")
                error = True
            else:
                eeg_archive_path = eeg_archive_local_path

        elif eeg_incoming_dir.startswith('s3://'):
            log_error_exit(
                env,
                f"{eeg_incoming_dir} is a S3 path but S3 server connection could not be established.",
                BAD_CONFIG_SETTING,
            )

        if not error:
            try:
                # Uncompress archive in tmp location
                eeg_collection_path = extract_archive(env, eeg_archive_path, 'EEG', tmp_dir)
            except Exception as err:
                log_error(env, f"Could not extract {eeg_archive_path} - {format(err)}")
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
                        log_error(env, f"Could not find a subject folder in the BIDS structure for {eeg_archive_file}.")
                        error = True
                        break

        if not error and not tmp_eeg_session_path:
            log_error(env, f"Could not find a session folder in the bids structure for {eeg_archive_file}.")
            error = True

        if not error:
            for modality in modalities:
                tmp_eeg_modality_path = os.path.join(tmp_eeg_session_path, modality)

                # if the EEG file was a set file, then update the filename for the .set
                # and .fdt files in the .set file so it can find the proper file for
                # visualization and analyses
                set_files = [
                    os.path.join(tmp_eeg_modality_path, file)
                    for file in os.listdir(tmp_eeg_modality_path)
                    if os.path.splitext(file)[1] == '.set'
                ]
                for set_full_path in set_files:
                    width_fdt_file = os.path.isfile(set_full_path.replace(".set", ".fdt"))

                    file_paths_updated = utilities.update_set_file_path_info(set_full_path, width_fdt_file)
                    if not file_paths_updated:
                        log_warning(env, f"Cannot update the set file {os.path.basename(set_full_path)} path info")

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
                        log_error(
                            env,
                            f"{tmp_eeg_modality_path} could not be uploaded to the S3 bucket. Error was\n{err}",
                        )

                        error = True
                else:
                    assembly_bids_path = config_db_obj.get_config("EEGAssemblyBIDS")
                    if not assembly_bids_path:
                        data_dir = config_db_obj.get_config("dataDirBasepath")
                        assembly_bids_path = os.path.join(data_dir, 'assembly_bids')

                    data_eeg_modality_path = os.path.join(assembly_bids_path, eeg_session_rel_path, modality)

                    # If the suject/session/modality BIDS data already exists
                    # on the destination folder, delete if first
                    # copying the data
                    remove_directory(env, data_eeg_modality_path)
                    copy_file(env, tmp_eeg_modality_path, data_eeg_modality_path)

        # Delete tmp location
        remove_directory(env, tmp_dir)

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

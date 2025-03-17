#!/usr/bin/env python

"""Script that ingests EEG BIDS datasets"""

import os
import subprocess
import sys

from scripts.delete_physiological_file import delete_physiological_file_in_db

from lib.database import Database
from lib.database_lib.config import Config
from lib.exitcode import INVALID_ARG, SUCCESS
from lib.lorisgetopt import LorisGetOpt

__license__ = "GPLv3"

sys.path.append('/home/user/python')


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " INGEST EEG BIDS DATASETS\n"
        "********************************************************************\n"
        "The program gets an EEG bids folder and ingest it into LORIS.\n\n"

        "usage  : ingest_eeg_bids_datasets.py -p <profile> -d <directory> ...\n\n"

        "options: \n"
        "\t-p, --profile            : Name of the python database config file in dicom-archive/.loris_mri\n"
        "\t-u, --upload_id          : ID of the upload (from electrophysiology_uploader) of the EEG dataset\n"
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
    profile = loris_getopt_obj.options_dict['profile']['value']

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
    assembly_bids_path = config_db_obj.get_config("EEGAssemblyBIDS")
    if not assembly_bids_path:
        data_dir = config_db_obj.get_config("dataDirBasepath")
        assembly_bids_path = os.path.join(data_dir, 'assembly_bids')

    # ---------------------------------------------------------------------------------------------
    # Get all EEG upload with status = Extracted
    # ---------------------------------------------------------------------------------------------
    query = "SELECT UploadID, SessionID" \
            " FROM electrophysiology_uploader" \
            " WHERE Status = 'Extracted'" \

    if upload_id:
        query = query + " AND UploadID = %s"
        eeg_dataset_list = db.pselect(query, (upload_id,))
    else:
        eeg_dataset_list = db.pselect(query, ())

    if not eeg_dataset_list:
        print('No new EEG datasets to ingest.')
        sys.exit(SUCCESS)

    # ---------------------------------------------------------------------------------------------
    # Ingestion
    # ---------------------------------------------------------------------------------------------

    for eeg_dataset in eeg_dataset_list:
        uploadid = str(eeg_dataset['UploadID'])

        query = "SELECT s.CandID, c.PSCID, s.Visit_label " \
            " FROM session s " \
            " JOIN candidate c ON c.CandID = s.CandID " \
            " WHERE s.ID = %s" \

        session_data = db.pselect(query, (eeg_dataset['SessionID'],))

        if not session_data:
            print(f'Session ID {eeg_dataset["SessionID"]} associated with UploadID {uploadid} does not exist.')
            sys.exit(INVALID_ARG)

        candid = session_data[0]['CandID']
        pscid = session_data[0]['PSCID']
        visit = session_data[0]['Visit_label']

        # Subject id
        subjectid = None
        # BIDS subject id is either the pscid or the candid

        # Try the candid
        if os.path.isdir(
            os.path.join(assembly_bids_path, 'sub-' + str(candid))
        ):
            subjectid = str(candid)

        # Try the pscid, case insensitive
        if not subjectid:
            gen = (
                dir for dir in os.listdir(assembly_bids_path)
                if dir.lower() == 'sub-' + pscid.lower()
            )
            subjectid = next(gen, None)

        # No match
        if not subjectid:
            print('No BIDS dataset matching candidate ' + pscid + ' ' + str(candid) + ' found.')
            continue

        # Visit
        path = os.path.join(assembly_bids_path, 'sub-' + subjectid, 'ses-' + visit)
        if not os.path.isdir(path):
            print(f'No BIDS dataset matching visit {visit} for candidate {pscid} {candid} found.')
            continue

        # Get previous upload files
        previous_eeg_files = db.pselect(
            "SELECT PhysiologicalFileID FROM physiological_file WHERE SessionID = %s",
            (eeg_dataset['SessionID'],)
        )
        # Delete previous uploads
        for previous_eeg_file in previous_eeg_files:
            delete_physiological_file_in_db(db, previous_eeg_file['PhysiologicalFileID'])

        # Assume eeg and raw data for now
        eeg_path = os.path.join(path, 'eeg')
        command = 'bids_import.py -p ' + profile + ' -d ' + eeg_path + ' --nobidsvalidation --nocopy --type raw'

        try:
            result = subprocess.run(command, shell = True, capture_output=True)

            if result.stdout:
                print(result.stdout.decode('utf-8'))

            if result.stderr:
                print(
                    f'ERROR: EEG Dataset with uploadID {uploadid} ingestion log:\n ' + result.stderr.decode('utf-8')
                )

            if result.returncode == 0:
                db.update(
                    "UPDATE electrophysiology_uploader SET Status = 'Ingested' WHERE UploadID = %s",
                    (uploadid,)
                )
                print('EEG Dataset with uploadID ' + uploadid + ' successfully ingested')

                continue

        except OSError:
            print('ERROR: error while executing bids_import.py')

        db.update(
            "UPDATE electrophysiology_uploader SET Status = 'Failed Ingestion' WHERE UploadID = %s",
            (uploadid,)
        )


if __name__ == "__main__":
    main()

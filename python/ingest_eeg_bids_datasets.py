#!/usr/bin/env python

"""Script that ingests EEG BIDS datasets"""

import os
import sys
from lib.lorisgetopt import LorisGetOpt
from lib.imaging_io import ImagingIO
from lib.database import Database
from lib.database_lib.config import Config
from lib.exitcode import SUCCESS, INVALID_ARG, PROGRAM_EXECUTION_FAILURE
from lib.log import Log
import subprocess

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
    tmp_dir = loris_getopt_obj.tmp_dir
    data_dir = config_db_obj.get_config("dataDirBasepath")
    assembly_bids_path = os.path.join(data_dir, 'assembly_bids')

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
        print('Session ID ' + eeg_dataset['SessionID'] + ' associated with UploadID ' + uploadid + ' does not exist.')
        sys.exit(INVALID_ARG)
         
      candid = session_data[0]['CandID']
      pscid = session_data[0]['PSCID']
      visit = session_data[0]['Visit_label']

      ## SUBJECT ID
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
       
      
      ## VISIT
      path = os.path.join(assembly_bids_path, 'sub-' + subjectid, 'ses-' + visit)
      if not os.path.isdir(path):
        print('No BIDS dataset matching visit ' + visit + ' for candidate ' + pscid + ' ' + str(candid) + ' found.')
        continue

      script = os.environ['LORIS_MRI'] + '/python/bids_import.py'
      eeg_path = os.path.join(path, 'eeg')
      command = 'python ' + script + ' -p ' + profile + ' -d ' + eeg_path + ' --nobidsvalidation --nocopy'
      
      try:
        result = subprocess.run(command, shell = True, capture_output=True)
        
        if result.stdout:
          print(result.stdout.decode('utf-8'))
        
        if not result.stderr:
          db.update(
            "UPDATE electrophysiology_uploader SET Status = 'Ingested' WHERE UploadID = %s",
            (uploadid,)
          )
          print('EEG Dataset with uploadID ' + uploadid + ' successfully ingested')
          continue

        print(f'ERROR: EEG Dataset with uploadID {uploadid} failed ingestion. Error was:\n ' + result.stderr.decode('utf-8'))
      
      except OSError:
        print('ERROR: ' + script + ' not found')

      db.update(
        "UPDATE electrophysiology_uploader SET Status = 'Failed Ingestion' WHERE UploadID = %s",
        (uploadid,)
      )
      
      # TODO: reupload of archive after ingestion
      # Delete if already exist

if __name__ == "__main__":
    main()

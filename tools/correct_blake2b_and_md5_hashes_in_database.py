#!/usr/bin/env python3

import lib.exitcode
import lib.utilities as utilities
import os
import shutil
import sys

from lib.database import Database
from lib.database_lib.config import Config
from lib.lorisgetopt import LorisGetOpt

__license__ = 'GPLv3'


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " CORRECT BLAKE2b AND MD5 HASHES STORED IN DATABASE SCRIPT\n"
        "********************************************************************\n"
        "The program will fetch the list of files stored in the database and update the hashes associated"
        " to them according to the correct algorithm to compute those hashes. (Before, the python scripts"
        " use to hash the path of the file instead of the data content).\n\n"

        "usage  : correct_blake2b_and_md5_hashes_in_database.py -p <profile> ...\n\n"

        "options: \n"
        "\t-p, --profile  : Name of the python database config file in dicom-archive/.loris_mri\n"
        "\t-v, --verbose  : If set, be verbose\n\n"

        "required options are: \n"
        "\t--profile\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
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

    # establish database connection
    verbose = loris_getopt_obj.options_dict['verbose']['value']
    db = Database(loris_getopt_obj.config_info.mysql, verbose)
    db.connect()

    # get data_dir path config
    config_db_obj = Config(db, verbose)
    data_dir = config_db_obj.get_config('dataDirBasepath')

    # get tmp dir path from loris_getopt object
    tmp_dir = loris_getopt_obj.tmp_dir

    # get S3 object from loris_getopt object
    s3_obj = loris_getopt_obj.s3_obj

    # handle imaging files to update their hashes values
    handle_imaging_files(db, data_dir, tmp_dir, s3_obj)

    # handle physiological files to update their hashes values
    handle_physiological_files(db, data_dir, tmp_dir, s3_obj)

    # delete temporary directory
    if os.path.exists(tmp_dir):
        shutil.rmtree(tmp_dir)

    # exit with SUCCESS exit code
    sys.exit(lib.exitcode.SUCCESS)


def handle_imaging_files(db, data_dir, tmp_dir, s3_obj):
    """
    Queries the list of FileIDs present in the files table and hashes present in parameter_file (along with the
    file path and hashes of associated BIDS/NIfTI files when they exist).
    Once the list has been established, compute the new MD5/BLAKE2b hashes and update the database entries
    with the new hash.
    Note: if the files are on S3, the file will first be downloaded so that hashes can be computed

    :param db: database object from the database.py class
     :type db: Database
    :param data_dir: path of the data_dir
     :type data_dir: str
    :param tmp_dir: path to a temporary directory for processing
     :type tmp_dir: str
    :param s3_obj: AWS A3 object from the aws_s3.py class
     :type s3_obj: AwsS3
    """

    # query list of FileIDs to process
    query_files = 'SELECT FileID, File AS FilePath FROM files'
    files_results = db.pselect(query_files, ())

    # loop through FileIDs and get all associated files and hashes stored in parameter_file
    for file_dict in files_results:
        query_hashes_and_associated_files_to_file_id(db, file_dict, s3_obj, tmp_dir, data_dir)

        # update imaging file's MD5 and blake2b hashes
        file_full_path = determine_file_full_path(file_dict['FilePath'], s3_obj, tmp_dir, data_dir)
        if 'md5hash' in file_dict.keys():
            new_md5_hash = utilities.compute_md5_hash(file_full_path)
            param_file_id = file_dict['md5hash']['ParameterFileID']
            update_parameter_file_hash(db, param_file_id, new_md5_hash)
        if 'file_blake2b_hash' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_full_path)
            param_file_id = file_dict['file_blake2b_hash']['ParameterFileID']
            update_parameter_file_hash(db, param_file_id, new_blake2b_hash)

        # update BIDS JSON file's blake2b hash if file present in database
        if 'bids_json_file' in file_dict.keys() and 'bids_json_file_blake2b_hash' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_dict['bids_json_file']['FullFilePath'])
            param_file_id = file_dict['bids_json_file_blake2b_hash']['ParameterFileID']
            update_parameter_file_hash(db, param_file_id, new_blake2b_hash)

        # update BVAL NIfTI file's blake2b hash if file present in database
        if 'check_bval_filename' in file_dict.keys() and 'check_bval_filename_blake2b_hash' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_dict['check_bval_filename']['FullFilePath'])
            param_file_id = file_dict['check_bval_filename_blake2b_hash']['ParameterFileID']
            update_parameter_file_hash(db, param_file_id, new_blake2b_hash)

        # update BVEC NIfTI file's blake2b hash if file present in database
        if 'check_bvec_filename' in file_dict.keys() and 'check_bvec_filename_blake2b_hash' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_dict['check_bvec_filename']['FullFilePath'])
            param_file_id = file_dict['check_bvec_filename_blake2b_hash']['ParameterFileID']
            update_parameter_file_hash(db, param_file_id, new_blake2b_hash)


def query_hashes_and_associated_files_to_file_id(db, file_dict, s3_obj, tmp_dir, data_dir):
    """
    Queries parameter_file table for the different file paths and hashes stored associated to a given FileID.
    Note: if file is on S3, the file will be downloaded from S3 before computing the hash.


    :param db: database object from the database.py class
     :type db: Database
    :param data_dir: path of the data_dir
     :type data_dir: str
    :param tmp_dir: path to a temporary directory for processing
     :type tmp_dir: str
    :param s3_obj: AWS A3 object from the aws_s3.py class
     :type s3_obj: AwsS3
    """

    list_of_parameter_type_to_query = [
        'md5hash',
        'file_blake2b_hash',
        'bids_json_file',
        'bids_json_file_blake2b_hash',
        'check_bval_filename',
        'check_bval_filename_blake2b_hash',
        'check_bvec_filename',
        'check_bvec_filename_blake2b_hash'
    ]

    query = 'SELECT pf.ParameterFileID, pf.Value' \
            ' FROM parameter_file pf JOIN parameter_type pt USING (ParameterTypeID)' \
            ' WHERE pt.Name=%s AND pf.FileID=%s'

    for param_type in list_of_parameter_type_to_query:

        results = db.pselect(query, (param_type, file_dict['FileID']))
        if not results:
            continue
        if param_type in ['bids_json_file', 'check_bval_filename', 'check_bvec_filename']:
            results[0]['FullFilePath'] = determine_file_full_path(results[0]['Value'], s3_obj, tmp_dir, data_dir)

        file_dict[param_type] = results[0]


def determine_file_full_path(file_rel_path, s3_obj, tmp_dir, data_dir):
    """
    Determines the full path to the file that will need to be inserted.

    :param file_rel_path: relative file path to data_dir
     :type file_rel_path: str
    :param s3_obj: AWS A3 object from the aws_s3.py class
     :type s3_obj: AwsS3
    :param tmp_dir: path to a temporary directory for processing
     :type tmp_dir: str
    :param data_dir: path of the data_dir
     :type data_dir: str

    :return: the full path to the file (if file was on S3, it will be downloaded before determining its full path)
     :rtype: str
    """

    full_file_path = ''
    if file_rel_path.startswith('s3://'):
        try:
            full_file_path = os.path.join(tmp_dir, os.path.basename(file_rel_path))
            s3_obj.download_file(file_rel_path, full_file_path)
        except Exception as err:
            print(
                f"[WARNING  ] {file_rel_path} could not be downloaded from S3 bucket."
                f" Error was\n{err}"
            )
            return full_file_path
    else:
        full_file_path = os.path.join(data_dir, file_rel_path)

    return full_file_path


def update_parameter_file_hash(db, param_file_id, new_hash):
    """
    Updates parameter_file table with the new hashes.

    :param db: database object
     :type db: Database
    :param param_file_id: ParameterFileID to use in the update statement
     :type param_file_id: str
    :param new_hash: new hash to use in the update statement
     :type new_hash: str
    """

    if not param_file_id or not new_hash:
        return

    query = "UPDATE parameter_file SET Value=%s WHERE ParameterFileID=%s"
    db.update(query, (new_hash, param_file_id))


def handle_physiological_files(db, data_dir, tmp_dir, s3_obj):
    """
    Queries the list of PhysiologicalFileIDs present in the physiological_file table and hashes present in
    physiological_parameter_file (along with the file path and hashes of associated BIDS files when they exist).
    Once the list has been established, compute the new MD5/BLAKE2b hashes and update the database entries
    with the new hash.
    Note: if the files are on S3, the file will first be downloaded so that hashes can be computed

    :param db: database object from the database.py class
     :type db: Database
    :param data_dir: path of the data_dir
     :type data_dir: str
    :param tmp_dir: path to a temporary directory for processing
     :type tmp_dir: str
    :param s3_obj: AWS A3 object from the aws_s3.py class
     :type s3_obj: AwsS3
    """

    # query list of PhysiologicalFileIDs to process
    query_files = 'SELECT PhysiologicalFileID, FilePath FROM physiological_file'
    phys_files_results = db.pselect(query_files, ())

    # loop through PhysiologicalFileIDs and get all associated files and hashes stored in physiological_parameter_file
    for file_dict in phys_files_results:
        query_hashes_and_associated_files_to_physiological_file_id(db, file_dict, s3_obj, tmp_dir, data_dir)

        file_full_path = determine_file_full_path(file_dict['FilePath'], s3_obj, tmp_dir, data_dir)
        if 'physiological_file_blake2b_hash' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_full_path)
            phys_param_file_id = file_dict['physiological_file_blake2b_hash']['PhysiologicalParameterFileID']
            update_phys_parameter_file_hash(db, phys_param_file_id, new_blake2b_hash)
        if 'physiological_json_file_blake2b_hash' in file_dict.keys() and 'eegjson_file' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_dict['eegjson_file']['FullFilePath'])
            phys_param_file_id = file_dict['physiological_json_file_blake2b_hash']['PhysiologicalParameterFileID']
            update_phys_parameter_file_hash(db, phys_param_file_id, new_blake2b_hash)
        if 'channel_file_blake2b_hash' in file_dict.keys() and 'channel_file' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_dict['channel_file']['FullFilePath'])
            phys_param_file_id = file_dict['channel_file_blake2b_hash']['PhysiologicalParameterFileID']
            update_phys_parameter_file_hash(db, phys_param_file_id, new_blake2b_hash)
        if 'electrode_file_blake2b_hash' in file_dict.keys() and 'electrode_file' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_dict['electrode_file']['FullFilePath'])
            phys_param_file_id = file_dict['electrode_file_blake2b_hash']['PhysiologicalParameterFileID']
            update_phys_parameter_file_hash(db, phys_param_file_id, new_blake2b_hash)
        if 'event_file_blake2b_hash' in file_dict.keys() and 'event_file' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_dict['event_file']['FullFilePath'])
            phys_param_file_id = file_dict['event_file_blake2b_hash']['PhysiologicalParameterFileID']
            update_phys_parameter_file_hash(db, phys_param_file_id, new_blake2b_hash)
        if 'physiological_scans_tsv_file_bake2hash' in file_dict.keys() and 'scans_tsv_file' in file_dict.keys():
            new_blake2b_hash = utilities.compute_blake2b_hash(file_dict['scans_tsv_file']['FullFilePath'])
            phys_param_file_id = file_dict['physiological_scans_tsv_file_bake2hash']['PhysiologicalParameterFileID']
            update_phys_parameter_file_hash(db, phys_param_file_id, new_blake2b_hash)


def query_hashes_and_associated_files_to_physiological_file_id(db, file_dict, s3_obj, tmp_dir, data_dir):
    """
    Queries physiological_parameter_file table for the different file paths and hashes stored associated to a given
    PhysiologicalFileID. Will also query tables physiological_channel, physiological_electrode and
    physiological_task_event to get the file path of those files as well.
    Note: if file is on S3, the file will be downloaded from S3 before computing the hash.

    :param db: database object from the database.py class
     :type db: Database
    :param data_dir: path of the data_dir
     :type data_dir: str
    :param tmp_dir: path to a temporary directory for processing
     :type tmp_dir: str
    :param s3_obj: AWS A3 object from the aws_s3.py class
     :type s3_obj: AwsS3
    """

    list_of_parameter_type_to_query = [
        'channel_file_blake2b_hash',
        'electrode_file_blake2b_hash',
        'event_file_blake2b_hash',
        'physiological_file_blake2b_hash',
        'eegjson_file',
        'physiological_json_file_blake2b_hash',
        'scans_tsv_file',
        'physiological_scans_tsv_file_bake2hash'
    ]

    query = 'SELECT ppf.PhysiologicalParameterFileID, ppf.Value' \
            ' FROM physiological_parameter_file ppf JOIN parameter_type pt USING (ParameterTypeID)' \
            ' WHERE pt.Name=%s AND ppf.PhysiologicalFileID=%s'

    for param_type in list_of_parameter_type_to_query:

        results = db.pselect(query, (param_type, file_dict['PhysiologicalFileID']))
        if not results:
            continue
        if param_type in ['scans_tsv_file', 'eegjson_file']:
            results[0]['FullFilePath'] = determine_file_full_path(results[0]['Value'], s3_obj, tmp_dir, data_dir)

        file_dict[param_type] = results[0]

    channel_file_results = db.pselect(
        "SELECT DISTINCT(FilePath) FROM physiological_channel WHERE PhysiologicalFileID=%s",
        (file_dict['PhysiologicalFileID'],)
    )
    if channel_file_results:
        file_dict['channel_file'] = {
            'FullFilePath': determine_file_full_path(channel_file_results[0]['FilePath'], s3_obj, tmp_dir, data_dir)
        }

    electrode_file_results = db.pselect(
        "SELECT DISTINCT(FilePath) FROM physiological_electrode WHERE PhysiologicalFileID=%s",
        (file_dict['PhysiologicalFileID'],)
    )
    if electrode_file_results:
        file_dict['electrode_file'] = {
            'FullFilePath': determine_file_full_path(electrode_file_results[0]['FilePath'], s3_obj, tmp_dir, data_dir)
        }

    event_file_results = db.pselect(
        "SELECT DISTINCT(FilePath) FROM physiological_task_event WHERE PhysiologicalFileID=%s",
        (file_dict['PhysiologicalFileID'],)
    )
    if event_file_results:
        file_dict['event_file'] = {
            'FullFilePath': determine_file_full_path(event_file_results[0]['FilePath'], s3_obj, tmp_dir, data_dir)
        }


def update_phys_parameter_file_hash(db, phys_param_file_id, new_hash):
    """
    Updates physiological_parameter_file table with the new hashes.

    :param db: database object
     :type db: Database
    :param phys_param_file_id: ParameterFileID to use in the update statement
     :type phys_param_file_id: str
    :param new_hash: new hash to use in the update statement
     :type new_hash: str
    """
    if not phys_param_file_id or not new_hash:
        return

    query = "UPDATE physiological_parameter_file SET Value=%s WHERE PhysiologicalParameterFileID=%s"
    db.update(query, (new_hash, phys_param_file_id))


if __name__ == "__main__":
    main()

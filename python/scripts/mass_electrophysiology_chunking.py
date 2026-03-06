#!/usr/bin/env python

"""Script to mass chunk electrophysiology datasets."""

import getopt
import sys

import lib.exitcode
import lib.utilities
from lib.config import get_data_dir_path_config
from lib.config_file import load_config
from lib.db.queries.physio_file import try_get_physio_file_with_id
from lib.env import Env
from lib.make_env import make_env
from lib.physio.chunking import create_physio_channels_chunks


def main():
    profile     = None
    verbose     = False
    smallest_id = None
    largest_id  = None

    long_options = [
        "help", "profile=", "smallest_id=", "largest_id=", "verbose"
    ]

    usage = (
        '\n'
        'usage  : mass_electrophysiology_chunking.py -p <profile> -s <smallest_id> '
                  '-l <largest_id>\n\n'
        'options: \n'
        '\t-p, --profile    : name of the python database config file in the config'
                              ' directory\n'
        '\t-s, --smallest_id: smallest PhyiologicalFileID to chunk\n'
        '\t-l, --largest_id : largest PhysiologicalFileID to chunk\n'
        '\t-v, --verbose    : be verbose\n'
    )

    try:
        opts, _ = getopt.getopt(sys.argv[1:], 'hp:s:l:v', long_options)
    except getopt.GetoptError:
        print(usage)
        sys.exit(lib.exitcode.GETOPT_FAILURE)

    for opt, arg in opts:
        if opt in ('-h', '--help'):
            print(usage)
            sys.exit()
        elif opt in ('-p', '--profile'):
            profile = arg
        elif opt in ('-s', '--smallest_id'):
            smallest_id = int(arg)
        elif opt in ('-l', '--largest_id'):
            largest_id = int(arg)
        elif opt in ('-v', '--verbose'):
            verbose = True

    # input error checking and load config_file file
    config_file = load_config(profile)
    input_error_checking(smallest_id, largest_id, usage)
    tmp_dir_path = lib.utilities.create_processing_tmp_dir('mass_nifti_pic')
    env = make_env('mass_nifti_pic', {}, config_file, tmp_dir_path, verbose)

    # run chunking script on electrophysiology datasets with a PhysiologicalFileID
    # between smallest_id and largest_id
    if (smallest_id == largest_id):
        make_chunks(env, smallest_id, config_file, verbose)
    else:
        for file_id in range(smallest_id, largest_id + 1):
            make_chunks(env, file_id)


def input_error_checking(smallest_id, largest_id, usage):
    """
    Checks whether the required inputs are correctly set.

    :param smallest_id: smallest PhysiologicalFileID on which to run the chunking script
     :type smallest_id: int
    :param largest_id : largest PhysiologicalFileID on which to run the chunking script
     :type largest_id : int
    :param usage      : script usage to be displayed when encountering an error
     :type usage      : str
    """

    if not smallest_id:
        message = '\n\tERROR: you must specify a smallest PhysiologyFileID on ' \
                  'which to run the chunking script using -s or --smallest_id option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if not largest_id:
        message = '\n\tERROR: you must specify a largest PhysiologyFileID on ' \
                  'which to run the chunking script using -l or --largest_id option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if not smallest_id <= largest_id:
        message = '\n\tERROR: the value for --smallest_id option is bigger than ' \
                  'value for --largest_id option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.INVALID_ARG)


def make_chunks(env: Env, physio_file_id: int):
    """
    Call the channel signal chunking script on the provided physiological file.
    """

    # grep config settings from the Config module
    data_dir = get_data_dir_path_config(env)

    # create the chunked dataset
    physio_file = try_get_physio_file_with_id(env.db, physio_file_id)
    if physio_file is not None:
        print(f"Chunking physiological file ID {physio_file.id}")
        create_physio_channels_chunks(env, physio_file, data_dir / physio_file.path)


if __name__ == "__main__":
    main()

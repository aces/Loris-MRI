#!/usr/bin/env python

"""Script to mass chunk electrophysiology datasets."""

import os
import sys
import getopt
import lib.exitcode
from lib.database      import Database
from lib.physiological import Physiological


__license__ = "GPLv3"


sys.path.append('/home/user/python')


# to limit the traceback when raising exceptions.
# sys.tracebacklimit = 0

def main():
    profile     = ''
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
        '\t-p, --profile    : name of the python database config file in '
                              'dicom-archive/.loris-mri\n'
        '\t-s, --smallest_id: smallest PhyiologicalFileID to chunk\n'
        '\t-l, --largest_id : largest PhysiologicalFileID to chunk\n'
        '\t-v, --verbose    : be verbose\n'
    )

    try:
        opts, args = getopt.getopt(sys.argv[1:], 'hp:s:l:v', long_options)
    except getopt.GetoptError as err:
        print(usage)
        sys.exit(lib.exitcode.GETOPT_FAILURE)

    for opt, arg in opts:
        if opt in ('-h', '--help'):
            print(usage)
            sys.exit()
        elif opt in ('-p', '--profile'):
            profile = os.environ['LORIS_CONFIG'] + "/.loris_mri/" + arg
        elif opt in ('-s', '--smallest_id'):
            smallest_id = int(arg)
        elif opt in ('-l', '--largest_id'):
            largest_id = int(arg)
        elif opt in ('-v', '--verbose'):
            verbose = True

    # input error checking and load config_file file
    config_file = input_error_checking(profile, smallest_id, largest_id, usage)

    # run chunking script on electrophysiology datasets with a PhysiologicalFileID
    # between smallest_id and largest_id
    if (smallest_id == largest_id):
        make_chunks(smallest_id, config_file, verbose)
    else:
        for file_id in range(smallest_id, largest_id):
            make_chunks(file_id, config_file, verbose)


def input_error_checking(profile, smallest_id, largest_id, usage):
    """
    Checks whether the required inputs are correctly set. If
    the path to the config_file file valid, then it will import the file as a
    module so the database connection information can be used to connect.

    :param profile    : path to the profile file with MySQL credentials
     :type profile    : str
    :param smallest_id: smallest PhysiologicalFileID on which to run the chunking script
     :type smallest_id: int
    :param largest_id : largest PhysiologicalFileID on which to run the chunking script
     :type largest_id : int
    :param usage      : script usage to be displayed when encountering an error
     :type usage      : str

    :return: config_file module with database credentials (config_file.mysql)
     :rtype: module
    """

    if not profile:
        message = '\n\tERROR: you must specify a profile file using -p or ' \
                  '--profile option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

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

    if os.path.isfile(profile):
        sys.path.append(os.path.dirname(profile))
        config_file = __import__(os.path.basename(profile[:-3]))
    else:
        message = '\n\tERROR: you must specify a valid profile file.\n' + \
                  profile + ' does not exist!'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.INVALID_PATH)

    return config_file


def make_chunks(physiological_file_id, config_file, verbose):
    """
    Call the function create_chunks_for_visualization of the Physiology class on
    the PhysiologicalFileID provided as argument to this function.

    :param physiological_file_id: PhysiologicalFileID of the file to chunk
     :type physiological_file_id: int
    :param config_file: path to the config file with database connection information
     :type config_file: str
    :param verbose    : flag for more printing if set
     :type verbose    : bool
    """

    # database connection
    db = Database(config_file.mysql, verbose)
    db.connect()

    # grep config settings from the Config module
    data_dir = db.get_config('dataDirBasepath')

    # making sure that there is a final / in data_dir
    data_dir = data_dir if data_dir.endswith('/') else data_dir + "/"

    # load the Physiological object
    physiological = Physiological(db, verbose)

    # create the chunked dataset
    if physiological.grep_file_path_from_file_id(physiological_file_id):
        print('Chunking physiological file ID ' + str(physiological_file_id))
        physiological.create_chunks_for_visualization(physiological_file_id, data_dir)


if __name__ == "__main__":
    main()

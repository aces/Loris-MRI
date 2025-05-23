#!/usr/bin/env python

"""Script to mass create the pic images of inserted NIfTI files."""

import getopt
import os
import re
import sys

import lib.exitcode
from lib.database import Database
from lib.database_lib.config import Config
from lib.imaging import Imaging

__license__ = "GPLv3"


sys.path.append('/home/user/python')


# to limit the traceback when raising exceptions.
# sys.tracebacklimit = 0

def main():
    profile     = ''
    verbose     = False
    force       = False
    smallest_id = None
    largest_id  = None

    long_options = [
        "help", "profile=", "smallest_id=", "largest_id=", "force", "verbose"
    ]

    usage = (
        '\n'
        'usage  : mass_nifti_pic.py -p <profile> -s <smallest_id> -l <largest_id>\n\n'
        'options: \n'
        '\t-p, --profile    : name of the python database config file in '
                              'dicom-archive/.loris-mri\n'
        '\t-s, --smallest_id: smallest FileID for which the pic will be created\n'
        '\t-l, --largest_id : largest FileID for which the pic will be created\n'
        '\t-f, --force      : overwrite the pic already present in the filesystem with new pic\n'
        '\t-v, --verbose    : be verbose\n'
    )

    try:
        opts, _ = getopt.getopt(sys.argv[1:], 'hp:s:l:fv', long_options)
    except getopt.GetoptError:
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
        elif opt in ('-f', '--force'):
            force = True
        elif opt in ('-v', '--verbose'):
            verbose = True

    # input error checking and load config_file file
    config_file = input_error_checking(profile, smallest_id, largest_id, usage)

    # create pic for NIfTI files with a FileID between smallest_id and largest_id
    if (smallest_id == largest_id):
        make_pic(smallest_id, config_file, force, verbose)
    else:
        for file_id in range(smallest_id, largest_id + 1):
            make_pic(file_id, config_file, force, verbose)


def input_error_checking(profile, smallest_id, largest_id, usage):
    """
    Checks whether the required inputs are correctly set. If
    the path to the config_file file valid, then it will import the file as a
    module so the database connection information can be used to connect.

    :param profile    : path to the profile file with MySQL credentials
     :type profile    : str
    :param smallest_id: smallest FileID for which to create the pic
     :type smallest_id: int
    :param largest_id : largest FileID for which to create the pic
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

    if os.path.isfile(profile):
        sys.path.append(os.path.dirname(profile))
        config_file = __import__(os.path.basename(profile[:-3]))
    else:
        message = f'\n\tERROR: you must specify a valid profile file.\n{profile} does not exist!'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.INVALID_PATH)

    if not smallest_id:
        message = '\n\tERROR: you must specify a smallest FileID on which to run the' \
                  ' mass_nifti_pic.py script using -s or --smallest_id option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if not largest_id:
        message = '\n\tERROR: you must specify a largest FileID on which to run the ' \
                  'mass_nifti_pic.py script using -l or --largest_id option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if not smallest_id <= largest_id:
        message = '\n\tERROR: the value for --smallest_id option is bigger than ' \
                  'value for --largest_id option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.INVALID_ARG)

    return config_file


def make_pic(file_id, config_file, force, verbose):
    """
    Call the function create_imaging_pic of the Imaging class on
    the FileID provided as argument to this function.

    :param file_id    : FileID of the file for which to create the pic
     :type file_id    : int
    :param config_file: path to the config file with database connection information
     :type config_file: str
    :param force      : if a pic is already present for the FileID, overwrite the pic in the filesystem with newly
                        generated pic
     :type force      : bool
    :param verbose    : flag for more printing if set
     :type verbose    : bool
    """

    # database connection
    db = Database(config_file.mysql, verbose)
    db.connect()

    # grep config settings from the Config module
    config_obj = Config(db, verbose)
    data_dir = config_obj.get_config('dataDirBasepath')

    # making sure that there is a final / in data_dir
    data_dir = data_dir if data_dir.endswith('/') else data_dir + "/"

    # load the Imaging object
    imaging = Imaging(db, verbose)

    # grep the NIfTI file path
    nii_file_path = imaging.grep_file_path_from_file_id(file_id)
    if not nii_file_path:
        print('WARNING: no file in the database with FileID = ' + str(file_id))
        return
    if not re.search(r'.nii.gz$', nii_file_path):
        print('WARNING: wrong file type. File ' + nii_file_path + ' is not a .nii.gz file')
        return
    if not os.path.exists(data_dir + nii_file_path):
        print('WARNING: file ' + nii_file_path + ' not found on the filesystem')
        return

    # checks if there is already a pic for the NIfTI file
    existing_pic_file_in_db = imaging.grep_parameter_value_from_file_id_and_parameter_name(
        file_id, 'check_pic_filename'
    )
    if existing_pic_file_in_db and not force:
        print('WARNING: there is already a pic for FileID ' + str(file_id) + '. Use -f or --force to overwrite it')
        return

    # grep the time length from the NIfTI file header
    is_4d_dataset = False
    length_parameters = imaging.get_nifti_image_length_parameters(data_dir + nii_file_path)
    if len(length_parameters) == 4:
        is_4d_dataset = True

    # grep the CandID of the file
    cand_id = imaging.grep_cand_id_from_file_id(file_id)
    if not cand_id:
        print('WARNING: CandID not found for FileID ' + str(file_id))

    # create the pic
    pic_rel_path = imaging.create_imaging_pic(
        {
            'cand_id'      : cand_id,
            'data_dir_path': data_dir,
            'file_rel_path': nii_file_path,
            'is_4D_dataset': is_4d_dataset,
            'file_id'      : file_id
        },
        existing_pic_file_in_db
    )
    if not os.path.exists(data_dir + 'pic/' + pic_rel_path):
        print('WARNING: the pic ' + data_dir + 'pic/' + pic_rel_path + 'was not created')
        return

    # insert the relative path to the pic in the parameter_file table
    if not existing_pic_file_in_db:
        imaging.insert_parameter_file(file_id, 'check_pic_filename', pic_rel_path)


if __name__ == "__main__":
    main()

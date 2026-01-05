#!/usr/bin/env python

"""Script to mass create the pic images of inserted NIfTI files."""

import getopt
import re
import sys

import lib.exitcode
import lib.utilities
from lib.config import get_data_dir_path_config
from lib.config_file import load_config
from lib.database import Database
from lib.db.queries.file import try_get_file_with_id
from lib.env import Env
from lib.imaging import Imaging
from lib.imaging_lib.file_parameter import register_mri_file_parameter
from lib.imaging_lib.nifti_pic import create_nifti_preview_picture
from lib.make_env import make_env


def main():
    profile     = None
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
        '\t-p, --profile    : name of the python database config file in the config'
                              ' directory\n'
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
            profile = arg
        elif opt in ('-s', '--smallest_id'):
            smallest_id = int(arg)
        elif opt in ('-l', '--largest_id'):
            largest_id = int(arg)
        elif opt in ('-f', '--force'):
            force = True
        elif opt in ('-v', '--verbose'):
            verbose = True

    # input error checking and load config_file file
    config_info = load_config(profile)
    input_error_checking(smallest_id, largest_id, usage)
    tmp_dir_path = lib.utilities.create_processing_tmp_dir('mass_nifti_pic')
    env = make_env('mass_nifti_pic', {}, config_info, tmp_dir_path, verbose)

    # create pic for NIfTI files with a FileID between smallest_id and largest_id
    if (smallest_id == largest_id):
        make_pic(env, smallest_id, config_info, force, verbose)
    else:
        for file_id in range(smallest_id, largest_id + 1):
            make_pic(env, file_id, config_info, force, verbose)


def input_error_checking(smallest_id, largest_id, usage):
    """
    Checks whether the required inputs are correctly set.

    :param smallest_id: smallest FileID for which to create the pic
     :type smallest_id: int
    :param largest_id : largest FileID for which to create the pic
     :type largest_id : int
    :param usage      : script usage to be displayed when encountering an error
     :type usage      : str
    """

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


def make_pic(env: Env, file_id, config_file, force, verbose):
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

    data_dir_path = get_data_dir_path_config(env)

    # load the Imaging object
    imaging = Imaging(db, verbose)

    # grep the NIfTI file path
    nifti_file = try_get_file_with_id(env.db, file_id)
    if nifti_file is None:
        print(f'WARNING: no file in the database with FileID = {file_id}')
        return
    if not re.search(r'.nii.gz$', str(nifti_file.path)):
        print(f'WARNING: wrong file type. File {nifti_file.path} is not a .nii.gz file')
        return
    if not (data_dir_path / nifti_file.path).exists():
        print(f'WARNING: file {nifti_file.path} not found on the filesystem')
        return

    # checks if there is already a pic for the NIfTI file
    existing_pic_file_in_db = imaging.grep_parameter_value_from_file_id_and_parameter_name(
        file_id, 'check_pic_filename'
    )
    if existing_pic_file_in_db and not force:
        print(f'WARNING: there is already a pic for FileID {nifti_file.id}. Use -f or --force to overwrite it')
        return

    # create the pic
    pic_rel_path = create_nifti_preview_picture(env, nifti_file)

    pic_path = data_dir_path / 'pic' / pic_rel_path
    if not pic_path.exists():
        print(f'WARNING: the pic {pic_path} was not created')
        return

    # insert the relative path to the pic in the parameter_file table
    if not existing_pic_file_in_db:
        register_mri_file_parameter(env, nifti_file, 'check_pic_filename', pic_rel_path)
        env.db.commit()


if __name__ == "__main__":
    main()

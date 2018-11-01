"""Set of utility functions."""

import os
import sys
import csv
import shutil
import filecmp
import tarfile
import lib.exitcode


__license__ = "GPLv3"


def read_tsv_file(tsv_file):
    """
    Reads a tsv file into a list of dictionaries

    :param tsv_file: tsv file to be read
     :type tsv_file: str

    :return: list of dictionaries read from the tsv file
     :rtype: list
    """

    results = []
    with open(tsv_file) as file:
        reader = csv.DictReader(file, delimiter="\t")

        for row in reader:
            results.append(row)

    return results


def copy_file(file_orig, file_copy, verbose):
    """
    Copies a file to a new location. If something goes wrong during the copy
    (either the file is not copied or the file already exists at the new
    location but differs from the original file), then will exit with proper
    message and exit code.

    :param file_orig: path to the original file
     :type file_orig: str
    :param file_copy: path to the copied file
     :type file_copy: str
    """

    if not os.path.exists(file_copy):
        if verbose:
            print("Copying file " + file_orig + " to " + file_copy)
        shutil.copyfile(file_orig, file_copy)
    elif not filecmp.cmp(file_orig, file_copy):
        # if files are not identical, then return file path to the copy and
        # a flag set to False to say that files were different
        message = '\n\tERROR: ' + file_orig + ' and ' + file_copy + ' differ\n'
        print(message)
        sys.exit(lib.exitcode.COPY_FAILURE)

    if not os.path.exists(file_copy):
        message = '\n\tERROR: failed copying ' + file_orig + \
                  ' to ' + file_copy + '\n'
        print(message)
        sys.exit(lib.exitcode.COPY_FAILURE)


def create_dir(dir_name, verbose):
    """
    Creates a directory. If the directory could not be created, then will
    exit with proper message and exit code.

    :param dir_name: full path of the directory to create
     :type dir_name: str

    :return: the full path of the created directory
     :rtype: str
    """

    if not os.path.exists(dir_name):
        if verbose:
            print("Creating directory " + dir_name)
        os.makedirs(dir_name)

    if not os.path.exists(dir_name):
        message = '\n\tERROR: could not create directory ' + dir_name + '\n'
        print(message)
        sys.exit(lib.exitcode.CREATE_DIR_FAILURE)

    return dir_name

def create_archive(files_to_archive, archive_rel_name, data_dir):
    """
    Creates an archive with the files listed in the files_to_archive tuple.

    :param files_to_archive: list of files to include in the archive
     :type files_to_archive: tuple
    :param archive_rel_name: name of the archive relative to data_dir
     :type archive_rel_name: str
    :param data_dir        : data_dir path
     :type data_dir        : str
    """

    # if the archive does not already exists, create it
    if not os.path.isfile(data_dir + archive_rel_name):
        tar = tarfile.open(data_dir + archive_rel_name, "w:gz")
        for file in files_to_archive:
            filename = os.path.basename(file)
            tar.add(file, arcname=filename, recursive=False)
        tar.close()

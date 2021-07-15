"""Set of utility functions."""

import os
import sys
import csv
import shutil
import subprocess
import filecmp
import tarfile
import scipy.io
import numpy
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
    with open(tsv_file, encoding='utf-8-sig') as file:
        reader = csv.DictReader(file, delimiter="\t")

        for row in reader:
            results.append(row)

    return results


def append_to_tsv_file(new_tsv_file, old_tsv_file, key_value_check, verbose):

    # verify that the header rows of the two TSV file are the same
    new_tsv_content = read_tsv_file(new_tsv_file)
    old_tsv_content = read_tsv_file(old_tsv_file)
    if new_tsv_content[0].keys() != old_tsv_content[0].keys():
        print(f"ERROR: participants.tsv columns differ between {new_tsv_file} and {old_tsv_file}")
        sys.exit(lib.exitcode.PROGRAM_EXECUTION_FAILURE)

    # loop through the rows of the new TSV file and check whether it is already present in the old TSV file
    for new_tsv_entry in new_tsv_content:
        if any(x[key_value_check] == new_tsv_entry[key_value_check] for x in old_tsv_content):
            if verbose:
                print(f"{new_tsv_entry[key_value_check]} already in {old_tsv_file}, no need to append")
        else:
            if verbose:
                print(f"Appending {new_tsv_entry[key_value_check]} to {old_tsv_file}")
            old_tsv_content.append(new_tsv_entry)

    with open(old_tsv_file, "w") as file:
        tsv_columns = old_tsv_content[0].keys()
        writer = csv.DictWriter(file, fieldnames=tsv_columns, delimiter='\t')
        writer.writeheader()
        for data in old_tsv_content:
            writer.writerow(data)


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


def update_set_file_path_info(set_file, fdt_file):
    """
    Updates the path info of the set file with the correct filenames for .set and
    .fdt files (for cases that had to be relabelled to include a Visit Label at
    the time of import.

    :param set_file: complete path of the .set file
     :type set_file: str
    :param fdt_file: complete path of the .fdt file
     :type fdt_file: str
    """

    # grep the basename without the extension of set_file
    basename = os.path.splitext(os.path.basename(set_file))[0]

    # read the .set EEG file using scipy
    dataset = scipy.io.loadmat(set_file)

    # update the EEG paths in the .set file
    dataset['EEG'][0][0][1]  = numpy.array(basename + ".set")
    if fdt_file:
        dataset['EEG'][0][0][15] = numpy.array(basename + ".fdt")
        dataset['EEG'][0][0][-1] = numpy.array(basename + ".fdt")

    # write the new .set file with the correct path info
    scipy.io.savemat(set_file, dataset, False)


def compute_md5sum(file):
    """
    Compute the md5sum of a file and returns it.

    :param file: file on which to compute the md5sum
     :type file: str

    :return: the md5sum of the file
     :rtype: str
    """

    if not os.path.exists(file):
        message = '\n\tERROR: file ' + file + ' not found\n'
        print(message)
        sys.exit(lib.exitcode.INVALID_PATH)

    out = subprocess.Popen(
        ['md5sum', file],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT
    )
    stdout, stderr = out.communicate()

    md5sum = stdout.split()[0].decode('ASCII')

    return md5sum

"""Set of utility functions."""

import csv
import filecmp
import io
import os
import re
import shutil
import sys
import tarfile
import tempfile
from datetime import datetime

import mat73
import numpy
import requests
import scipy.io
from typing_extensions import deprecated

import lib.exitcode
import lib.util.crypto

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
    """
    This function will compare the content of two TSV files and append missing values
    from the new TSV file into the old TSV file.

    :param new_tsv_file: TSV file with new values
     :type new_tsv_file: str
    :param old_tsv_file: the TSV file that will be modified with new values
     :type old_tsv_file: str
    :param key_value_check: the key to the value to use to check if an entry is already there
                            example: participant_id
     :type key_value_check: str
    :param verbose: whether verbose messages should be printed out
     :type verbose: bool
    """

    # verify that the header rows of the two TSV file are the same
    new_tsv_content = read_tsv_file(new_tsv_file)
    old_tsv_content = read_tsv_file(old_tsv_file)
    tsv_basename = os.path.basename(new_tsv_file)
    if new_tsv_content[0].keys() != old_tsv_content[0].keys():
        print(f"ERROR: {tsv_basename} columns differ between {new_tsv_file} and {old_tsv_file}")
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


def create_archive(files_to_archive, archive_path):
    """
    Creates an archive with the files listed in the files_to_archive tuple.

    :param files_to_archive: list of files to include in the archive
     :type files_to_archive: tuple
    :param archive_path: full path of archive
     :type archive_path: str
    """

    # if the archive does not already exists, create it
    if not os.path.isfile(archive_path):
        tar = tarfile.open(archive_path, "w:gz")
        for file in files_to_archive:
            filename = os.path.basename(file)
            tar.add(file, arcname=filename, recursive=False)
        tar.close()


def update_set_file_path_info(set_file, with_fdt_file):
    """
    Updates the path info of the set file with the correct filenames for .set and
    .fdt files (for cases that had to be relabelled to include a Visit Label at
    the time of import.

    :param set_file: complete path of the .set file
     :type set_file: str
    :param with_fdt_file: Confirm presence of a matching .fdt file
     :type with_fdt_file: bool
    """

    # grep the basename without the extension of set_file
    basename = os.path.splitext(os.path.basename(set_file))[0]
    set_file_name = numpy.array(basename + ".set")
    fdt_file_name = numpy.array(basename + ".fdt")

    try:
        # read the .set EEG file using scipy
        dataset = scipy.io.loadmat(set_file)

        # update the EEG paths in the .set file
        if 'filename' in dataset.keys():
            dataset['filename'] = set_file_name
        if 'setname' in dataset.keys():
            dataset['setname'] = numpy.array(basename)
        if 'EEG' in dataset.keys():
            dataset['EEG'][0][0][1] = set_file_name
        if with_fdt_file and 'EEG' in dataset.keys():
            dataset['EEG'][0][0][15] = fdt_file_name
            dataset['EEG'][0][0][40] = fdt_file_name

        # write the new .set file with the correct path info
        scipy.io.savemat(set_file, dataset, False)
    except NotImplementedError:     # Thrown for matlab v7.3 files
        # read the .set EEG file using skjerns/mat7.3
        dataset = mat73.loadmat(set_file, only_include=['filename', 'datfile'])

        if 'filename' not in dataset.keys() or \
                dataset['filename'] != set_file_name:
            print(f'Expected `filename` field: {set_file_name}')
            return False

        if with_fdt_file:
            if 'datfile' not in dataset.keys() or \
                    dataset['datfile'] != fdt_file_name:
                print(f'Expected `datfile` field: {fdt_file_name}')
                return False

    return True


@deprecated('Use `lib.util.crypto.compute_file_blake2b_hash` instead.')
def compute_blake2b_hash(file_path):
    """
    Compute the blake2b hash of a file and returns it.
    :param file_path: path to the file on which to compute the blake2b hash
     :type file_path: str
    :return: the blake2b hash of the file
     :rtype: str
    """
    if os.path.exists(file_path):
        return lib.util.crypto.compute_file_blake2b_hash(file_path)


@deprecated('Use `lib.util.crypto.compute_file_md5_hash` instead.')
def compute_md5_hash(file_path):
    """
    Compute the md5 hash of a file and returns it.
    :param file_path: path to the file on which to compute the md5 hash
     :type file_path: str
    :return: the md5 hash of the file
     :rtype: str
    """
    if os.path.exists(file_path):
        return lib.util.crypto.compute_file_md5_hash(file_path)


def create_processing_tmp_dir(template_prefix):
    """
    Creates a temporary directory with a name based on the concatenation of the
    template prefix name given as an argument and the date and time the function
    was called.

    :param template_prefix: a template prefix to use for the name of the tmp dir
     :type template_prefix: str

    :return: absolute path to the created temporary directory
     :rtype: str
    """

    # get the value for the OS environment TMPDIR
    env_tmp_dir = os.environ.get("TMPDIR")

    # append date and time information to the prefix name for the tmp dir
    now = datetime.now()
    template_prefix += f"_{now.strftime('%Y-%m-%d_%Hh%Mm%Ss_')}"

    # create the temporary directory and return it
    tmp_dir = tempfile.mkdtemp(prefix=template_prefix, dir=env_tmp_dir)

    return tmp_dir


@deprecated('Use `lib.util.fs.remove_empty_subdirectories` instead')
def remove_empty_folders(path_abs):

    walk = list(os.walk(path_abs))
    for path, _, _ in walk[::-1]:
        if len(os.listdir(path)) == 0:
            os.rmdir(path)


def assemble_hed_service(data_dir, event_tsv_path, event_json_path):
    # Using HED Tool Rest Services to assemble the HED Tags
    # https://hed-examples.readthedocs.io/en/latest/HedToolsOnline.html#hed-restful-services

    # Request CSRF Token & session cookie
    request_token_url = 'https://hedtools.ucsd.edu/hed/services'
    token_response = requests.get(request_token_url)

    cookie = token_response.headers['Set-Cookie']
    token = re.search(r'csrf_token" value="(.+?)"', token_response.text).group(1)

    # Define headers for assemble POST request, containing token and cookie
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRFToken": token,
        "Cookie": cookie
    }

    # Read event files as str
    event_json_text = open(data_dir + event_json_path).read()
    event_tsv_text = open(data_dir + event_tsv_path).read()

    # Define request parameters
    params = {
        'service': 'events_assemble',
        'schema_version': '8.0.0',
        'json_string': event_json_text,
        'events_string': event_tsv_text,
        'check_for_warnings': 'off',
        'expand_defs': 'on',
        'columns_included': ['onset']
    }

    # Make the request to assemble
    request_assemble_url = 'https://hedtools.ucsd.edu/hed/services_submit'
    assemble_response = requests.post(
        request_assemble_url, headers=headers, json=params
    )

    # get assembled results as dictionary
    data = assemble_response.json()['results']['data']
    results = list(csv.DictReader(io.StringIO(data), delimiter='\t'))

    return results

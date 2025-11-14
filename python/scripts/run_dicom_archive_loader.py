#!/usr/bin/env python

"""Script that loads a DICOM archive and generate BIDS files to be inserted into the database"""

import os

from lib.dcm2bids_imaging_pipeline_lib.dicom_archive_loader_pipeline import DicomArchiveLoaderPipeline
from lib.lorisgetopt import LorisGetOpt


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " NIfTI/JSON FILE INSERTION SCRIPT\n"
        "********************************************************************\n"
        "The program determines NIfTI file protocol and insert it (along with its"
        " JSON sidecar file) into the files table.\n\n"
        # TODO more description on how the script works

        "usage  : run_dicom_archive_loader.py -p <profile> -u <upload_id> ...\n\n"

        "options: \n"
        "\t-p, --profile            : Name of the python database config file in config\n"
        "\t-t, --tarchive_path      : Absolute path to the DICOM archive to process\n"
        "\t-u, --upload_id          : ID of the upload (from mri_upload) related to the DICOM archive to process\n"
        "\t-s, --series_uid         : Only insert the provided SeriesUID\n"
        "\t-f, --force              : If set, forces the script to run even if DICOM archive validation has failed\n"
        "\t-v, --verbose            : If set, be verbose\n\n"

        "required options are: \n"
        "\t--tarchive_path OR --upload_id\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "tarchive_path": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "t", "is_path": True
        },
        "upload_id": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "u", "is_path": False
        },
        "series_uid": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "s", "is_path": False
        },
        "force": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "f", "is_path": False
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

    # input error checking and load config_file file
    input_error_checking(loris_getopt_obj)

    # nifti validation and insertion
    DicomArchiveLoaderPipeline(loris_getopt_obj, os.path.basename(__file__[:-3]))


def input_error_checking(loris_getopt_obj):

    # check that only one of tarchive_path, upload_id or force has been provided
    loris_getopt_obj.check_tarchive_path_upload_id_or_force_set()


if __name__ == "__main__":
    main()

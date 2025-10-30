#!/usr/bin/env python

"""Script that inserts NIfTI/JSON files into the database"""

import os
import sys

import lib.exitcode
from lib.dcm2bids_imaging_pipeline_lib.nifti_insertion_pipeline import NiftiInsertionPipeline
from lib.lorisgetopt import LorisGetOpt

sys.path.append('/home/user/python')


# to limit the traceback when raising exceptions.
# sys.tracebacklimit = 0


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " NIfTI/JSON FILE INSERTION SCRIPT\n"
        "********************************************************************\n"
        "The program determines NIfTI file protocol and insert it (along with its"
        " JSON sidecar file) into the files table.\n\n"
        # TODO more description on how the script works

        "usage  : run_nifti_insertion.py -p <profile> -n <nifti_path> -j <json_path> ...\n\n"

        "options: \n"
        "\t-p, --profile            : Name of the python database config file in config\n"
        "\t-n, --nifti_path         : Absolute path to the NIfTI file to insert\n"
        "\t-j, --json_path          : Absolute path to the BIDS JSON sidecar file with scan parameters\n"
        "\t-l, --bval_path          : Absolute path to the NIfTI BVAL file for DWI acquisitions\n"
        "\t-e, --bvec_path          : Absolute path to the NIfTI BVEC file for DWI acquisitions\n"
        "\t-t, --tarchive_path      : Absolute path to the DICOM archive linked to the NIfTI file\n"
        "\t-u, --upload_id          : ID of the upload (from mri_upload) linked to the NIfTI file\n"
        "\t-s, --loris_scan_type    : LORIS scan type from the mri_scan_type table\n"
        "\t-b, --bypass_extra_checks: If set, bypasses the extra protocol validation checks\n"
        "\t-c, --create_pic         : If set, creates the pic to be displayed in the imaging browser\n"
        "\t-f, --force              : If set, forces the insertion of the NIfTI file\n"
        "\t-v, --verbose            : If set, be verbose\n\n"

        "required options are: \n"
        "\t--nifti_path\n"
        "\t--json_path OR --loris_scan_type\n"
        "\t--tarchive_path OR --upload_id\n"
        "\tif --force is set, please provide --loris_scan_type as well\n\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "nifti_path": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "n", "is_path": True
        },
        "json_path": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "j", "is_path": True
        },
        "bval_path": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "l", "is_path": True
        },
        "bvec_path": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "e", "is_path": True
        },
        "tarchive_path": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "t", "is_path": True
        },
        "upload_id": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "u", "is_path": False
        },
        "loris_scan_type": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "s", "is_path": False
        },
        "bypass_extra_checks": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "b", "is_path": False
        },
        "create_pic": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "c", "is_path": False
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
    NiftiInsertionPipeline(loris_getopt_obj, os.path.basename(__file__[:-3]))


def input_error_checking(loris_getopt_obj):

    # check that only one of tarchive_path, upload_id or force has been provided
    loris_getopt_obj.check_tarchive_path_upload_id_or_force_set()

    # check that json_path or loris_scan_type has been provided (both can be provided)
    json_path = loris_getopt_obj.options_dict["json_path"]["value"]
    scan_type = loris_getopt_obj.options_dict["loris_scan_type"]["value"]
    if not json_path and not scan_type:
        print(
            "[ERROR   ] a json_path or a loris_scan_type need to be provided in order"
            " to determine the image file protocol.\n"
        )
        sys.exit(lib.exitcode.MISSING_ARG)


if __name__ == "__main__":
    main()

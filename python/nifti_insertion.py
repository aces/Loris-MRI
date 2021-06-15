#!/usr/bin/env python

"""Script that inserts NIfTI/JSON files into the database"""

import getopt
import os
import sys

import lib.exitcode
from lib.database import Database
from lib.lorisgetopt import LorisGetOpt

__license__ = "GPLv3"


sys.path.append('/home/user/python')

# to limit the traceback when raising exceptions.
#sys.tracebacklimit = 0



def main():

    usage = (
        "\n"

        "********************************************************************\n"
        " NIfTI/JSON FILE INSERTION SCRIPT\n"
        "********************************************************************\n"
        "The program determines NIfTI file protocol and insert it (along with its"
        " JSON sidecar file) into the files table.\n\n"
        # TODO more description on how the script works

        "usage  : nifti_insertion.py -p <profile> -n <nifti_path> -j <json_path> ...\n\n"

        "options: \n"
        "\t-p, --profile            : Name of the python database config file in dicom-archive/.loris_mri\n"
        "\t-n, --nifti_path         : Absolute path to the NIfTI file to insert\n"
        "\t-j, --json_path          : Absolute path to the BIDS JSON sidecar file with scan parameters\n"
        "\t-t, --tarchive_path      : Absolute path to the DICOM archive linked to the NIfTI file\n"
        "\t-u, --upload_id          : ID of the upload (from mri_upload) linked to the NIfTI file\n"
        "\t-s, --loris_scan_type    : LORIS scan type from the mri_scan_type table\n"
        "\t-b, --bypass_extra_checks: If set, bypasses the extra protocol validation checks\n"
        "\t-c, --create_pic         : If set, creates the pic to be displayed in the imaging browser\n"
        "\t-f, --force              : If set, forces the insertion of the NIfTI file\n"
        "\t-v, --verbose            : If set, be verbose\n"

        "required options are: \n"
        "--profile\n"
        "--nifti_path\n"
        "--json_path OR --loris_scan_type\n"
        "--tarchive OR --upload_id\n"
        "if --force is set, please provide --loris_scan_type as well\n"
    )

    options_dict = {
        "profile": {
            "value": None,  "required": True,  "expect_arg": True,  "short_opt": "p", "is_path": True
        },
        "nifti_path": {
            "value": None,  "required": True,  "expect_arg": True,  "short_opt": "n", "is_path": True
        },
        "json_path": {
            "value": None,  "required": False, "expect_arg": True,  "short_opt": "j", "is_path": True
        },
        "tarchive_path": {
            "value": None,  "required": False, "expect_arg": True,  "short_opt": "t", "is_path": True
        },
        "upload_id": {
            "value": None,  "required": False, "expect_arg": True,  "short_opt": "u", "is_path": False
        },
        "loris_scan_type": {
            "value": None,  "required": False, "expect_arg": True,  "short_opt": "s", "is_path": False
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

    loris_getopt_obj = LorisGetOpt(usage, options_dict)
    long_options_list = loris_getopt_obj.long_options
    short_options_list = loris_getopt_obj.short_options

    try:
        opts, args = getopt.getopt(sys.argv[1:], ''.join(short_options_list), long_options_list)
    except getopt.GetoptError as err:
        print(err)
        print(usage)
        sys.exit(lib.exitcode.GETOPT_FAILURE)

    loris_getopt_obj.populate_options_dict_values(opts)

    print(options_dict)

    # input error checking and load config_file file
    config_file = input_error_checking(loris_getopt_obj)


def input_error_checking(loris_getopt_obj):

    # check that all required options are set

    config_file = "hello"

    return config_file


if __name__ == "__main__":
    main()

# TODO: plan
# 1. script instantiation and argument checks


# 2. database connection
# 3. create tmp directory and log file

# 4. check that file is unique. if already registered, log it

# 5. check if the archive is validated
# 6. create tarchive array

# 7. load nifti and JSON file
# 8. determine PSC
# 9. determine scanner ID
# 10. determine subject ID
# 11. validate subject IDs, exits if not valid
# 12. if file not associated to a tarchiveID or uploadID, check that cannot find it in tarchive tables. If so, exits
# 13. get more information about the scan (scanner, IDs, dates...)
# 14. get session information, exits if incorrect
# 15. check if file is unique
# 16. determine acquisition protocol
# 17. insert into Db
# 18. update mri violations log
# 19. create pics



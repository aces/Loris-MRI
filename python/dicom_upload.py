#!/usr/bin/env python

"""Script to import BIDS structure into LORIS."""

import os
from lib.api.post_candidate_dicom_processes import post_candidate_dicom_processes
from lib.lorisgetopt import LorisGetOpt
import lib.api
from lib.api.get_candidate_dicom import get_candidate_dicom
from lib.api.post_candidate_dicom import post_candidate_dicom
from lib.dataclass.api import Api


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " DICOM UPLOAD SCRIPT\n"
        "********************************************************************\n"
        "The program sends a DICOM study to the LORIS API, which will register it in the database\n"
        "and call back the imaging pipeline scripts to process it adequately."

        "usage  : dicom_upload.py -p <profile> -s <source_dir> -t <target_dir> ...\n\n"

        "options: \n"
        "\t-p, --profile   : Name of the python database config file in dicom-archive/.loris_mri\n"
        "\t-d, --dicoms    : Archive containing the DICOMS of the study to upload\n"
        "\t-u  --user      : Username of the LORIS user responsible for this upload\n"
        "\t-p  --pass      : Password of the LORIS user responsible for this upload\n"
        "\t-v, --verbose   : If set, be verbose\n\n"

        "required options are: \n"
        "\t--profile\n"
        "\t--dicoms\n"
        "\t--user\n"
        "\t--pass\n\n"
    )

    # NOTE: Some options do not have short options but LorisGetOpt does not support that, so we
    # repeat the long names.
    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "dicoms": {
            "value": None,  "required": True,  "expect_arg": True, "short_opt": "d", "is_path": True,
        },
        "user": {
            "value": None,  "required": True,  "expect_arg": True, "short_opt": "u", "is_path": False,
        },
        "pass": {
            "value": None,  "required": True,  "expect_arg": True, "short_opt": "p", "is_path": False,
        },
        "verbose": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "v", "is_path": False,
        },
        "help": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "h", "is_path": False,
        },
    }

    # get the options provided by the user
    loris_getopt_obj = LorisGetOpt(usage, options_dict, os.path.basename(__file__[:-3]))

    # Typed arguments

    arg_profile:   str | None = loris_getopt_obj.options_dict['profile']['value']
    arg_dicoms:    str        = loris_getopt_obj.options_dict['dicoms']['value']
    arg_user:      str        = loris_getopt_obj.options_dict['user']['value']
    arg_pass:      str        = loris_getopt_obj.options_dict['pass']['value']
    arg_verbose:   bool       = loris_getopt_obj.options_dict['verbose']['value']
    api = Api.from_credentials('https://mmulder-dev.loris.ca', arg_user, arg_pass)
    # get(post_candidate_dicom(api, 587630, 'V1'))
    # print(post_candidate_dicom(api, 587630, 'DCC090', 'V1', False, arg_dicoms))
    print(post_candidate_dicom_processes(api, 587630, 'V1', 'DCC090_587630_V1.tar', 126))

if __name__ == "__main__":
    main()

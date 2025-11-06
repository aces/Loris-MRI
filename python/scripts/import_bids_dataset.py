#!/usr/bin/env python

"""Script to import BIDS structure into LORIS."""

import os
from typing import Any

import lib.exitcode
from lib.import_bids_dataset.args import Args
from lib.import_bids_dataset.main import import_bids_dataset
from lib.logging import log_error_exit
from lib.lorisgetopt import LorisGetOpt
from lib.make_env import make_env


def pack_args(options_dict: dict[str, Any]) -> Args:
    return Args(
        source_bids_path = os.path.normpath(options_dict['directory']['value']),
        type             = options_dict['type']['value'],
        bids_validation  = not options_dict['nobidsvalidation']['value'],
        create_candidate = options_dict['createcandidate']['value'],
        create_session   = options_dict['createsession']['value'],
        copy             = not options_dict['nocopy']['value'],
        verbose          = options_dict['verbose']['value'],
    )


# to limit the traceback when raising exceptions.
# sys.tracebacklimit = 0

def main():
    usage = (
        "\n"
        "usage  : bids_import -d <bids_directory> -p <profile> \n"
        "\n"
        "options: \n"
        "\t-p, --profile          : name of the python database config file in dicom-archive/.loris-mri\n"
        "\t-d, --directory        : BIDS directory to parse & insert into LORIS\n"
        "\t                         If directory is within $data_dir/assembly_bids, no copy will be performed\n"
        "\t-c, --createcandidate  : to create BIDS candidates in LORIS (optional)\n"
        "\t-s, --createsession    : to create BIDS sessions in LORIS (optional)\n"
        "\t-b, --nobidsvalidation : to disable BIDS validation for BIDS compliance\n"
        "\t-a, --nocopy           : to disable dataset copy in data assembly_bids\n"
        "\t-t, --type             : raw | derivative. Specify the dataset type.\n"
        "\t                         If not set, the pipeline will look for both raw and derivative files.\n"
        "\t                         Required if no dataset_description.json is found.\n"
        "\t-v, --verbose          : be verbose\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "directory": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "d", "is_path": True
        },
        "createcandidate": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "c", "is_path": False
        },
        "createsession": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "s", "is_path": False
        },
        "nobidsvalidation": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "b", "is_path": False
        },
        "nocopy": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "a", "is_path": False
        },
        "type": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "t", "is_path": False
        },
        "verbose": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "v", "is_path": False
        },
        "help": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "h", "is_path": False
        },
    }

    # Get the CLI arguments and initiate the environment.

    loris_getopt_obj = LorisGetOpt(usage, options_dict, os.path.basename(__file__[:-3]))

    env = make_env(loris_getopt_obj)

    # Check the CLI arguments.

    type = loris_getopt_obj.options_dict['type']['value']
    if type not in (None, 'raw', 'derivative'):
        log_error_exit(
            env,
            f"--type must be one of 'raw', 'derivative'\n{usage}",
            lib.exitcode.MISSING_ARG,
        )

    args = pack_args(loris_getopt_obj.options_dict)

    # read and insert BIDS data
    import_bids_dataset(
        env,
        args,
        loris_getopt_obj.db,
    )

    print("Success !")


if __name__ == '__main__':
    main()

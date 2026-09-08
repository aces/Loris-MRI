#!/usr/bin/env python

from pathlib import Path
from typing import Any

import lib.exitcode
from lib.logging import log_error_exit
from lib.lorisgetopt import LorisGetOpt

from loris_bids_importer.importer import BidsImporterArgs
from loris_bids_importer.main import import_bids_dataset


def pack_args(options_dict: dict[str, Any]) -> BidsImporterArgs:
    return BidsImporterArgs(
        source_bids_path = Path(options_dict['directory']['value']),
        type             = options_dict['type']['value'],
        bids_validation  = not options_dict['no-bids-validation']['value'],
        create_candidate = options_dict['create-candidate']['value'],
        create_session   = options_dict['create-session']['value'],
        copy             = not options_dict['no-copy']['value'],
        verbose          = options_dict['verbose']['value'],
    )


def main():
    usage = (
        "\n"
        "usage  : import-bids-dataset -d <bids_directory> \n"
        "\n"
        "options: \n"
        "\t-p, --profile            : name of the python database config file in dicom-archive/.loris-mri\n"
        "\t-d, --directory          : BIDS directory to parse & insert into LORIS\n"
        "\t                           If directory is within $data_dir/assembly_bids, no copy will be performed\n"
        "\t-c, --create-candidate   : to create BIDS candidates in LORIS (optional)\n"
        "\t-s, --create-session     : to create BIDS sessions in LORIS (optional)\n"
        "\t-b, --no-bids-validation : to disable BIDS validation for BIDS compliance\n"
        "\t-a, --no-copy            : to disable dataset copy in data assembly_bids\n"
        "\t-t, --type               : raw | derivative. Specify the dataset type.\n"
        "\t                           If not set, the pipeline will look for both raw and derivative files.\n"
        "\t                           Required if no dataset_description.json is found.\n"
        "\t-v, --verbose            : be verbose\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "directory": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "d", "is_path": True
        },
        "create-candidate": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "c", "is_path": False
        },
        "create-session": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "s", "is_path": False
        },
        "no-bids-validation": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "b", "is_path": False
        },
        "no-copy": {
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

    loris_getopt_obj = LorisGetOpt(usage, options_dict, 'import-bids-dataset')

    env = loris_getopt_obj.env

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

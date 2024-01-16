#!/usr/bin/env python3

import lib.exitcode
import os

from lib.database import Database
from lib.lorisgetopt import LorisGetOpt


__license__ = 'GPLv3'


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " CORRECT BLAKE2b AND MD5 HASHES STORED IN DATABASE SCRIPT\n"
        "********************************************************************\n"
        "TODO\n\n"  # TODO

        "usage  : correct_lists_incorrectly_saved_in_parameter_file.py -p <profile> ...\n\n"

        "options: \n"
        "\t-p, --profile  : Name of the python database config file in dicom-archive/.loris_mri\n"
        "\t-v, --verbose  : If set, be verbose\n\n"

        "required options are: \n"
        "\t--profile\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
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

    # establish database connection
    verbose = loris_getopt_obj.options_dict['verbose']['value']
    db = Database(loris_getopt_obj.config_info.mysql, verbose)
    db.connect()

    # get the list of entries in parameter_file to correct and correct them
    get_list_of_entries_in_parameter_file_to_correct(db)


def get_list_of_entries_in_parameter_file_to_correct(db):

    results = db.pselect('SELECT * FROM parameter_file WHERE Value LIKE %s', ('[[%%]]',))

    for row in results:
        param_file_id = row['ParameterFileID']
        value_str = row['Value']
        new_value_str = value_str.replace("[[, ', ", "[").replace(", ', ]]", "]").replace(", ", "").replace("'", "")
        new_value_str = new_value_str.replace(" ", '').replace(",", ", ").replace("[[", "[").replace("]]", "]")
        db.update('UPDATE parameter_file SET Value=%s WHERE ParameterFileID=%s', (new_value_str, param_file_id))


if __name__ == "__main__":
    main()

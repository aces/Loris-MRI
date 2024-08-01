#!/usr/bin/env python

import os
import sys

from lib.database_lib.config import Config
from lib.exception.determine_subject_exception import DetermineSubjectException
from lib.exception.validate_subject_exception import ValidateSubjectException
import lib.exitcode
from lib.imaging import Imaging
from lib.log import Log
import lib.utilities
from lib.lorisgetopt import LorisGetOpt
from lib.dcm2bids_imaging_pipeline_lib.nifti_insertion_pipeline import NiftiInsertionPipeline
from lib.validate_subject_ids import validate_subject_name

__license__ = "GPLv3"

sys.path.append('/home/user/python')


# to limit the traceback when raising exceptions.
# sys.tracebacklimit = 0


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " SUBJECT VALIDATION CHECKING SCRIPT\n"
        "********************************************************************\n"
        "This scripts determines if a non-phantom subject's name is correctly formatted and \n"
        "matches the IDs present in the database. It mainly exists to be called from the Perl \n"
        "imaging pipeline.\n"
        "\n"

        "usage  : validate_subject_ids.py -p <profile> -s <subject_name>\n\n"

        "options: \n"
        "\t-p, --profile : Name of the python database config file in dicom-archive/.loris_mri\n"
        "\t-s, --subject : Name of the subject, which is valid.\n"
        "\t-v, --verbose : If set, be verbose\n\n"

        "required options are: \n"
        "\t--profile\n"
        "\t--subject\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "subject": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "s", "is_path": False
        },
        "verbose": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "v", "is_path": False
        },
    }

    # Get the options provided by the user
    loris_getopt_obj = LorisGetOpt(usage, options_dict, os.path.basename(__file__[:-3]))
    opt_verbose = loris_getopt_obj.options_dict['verbose']['value']
    opt_subject = loris_getopt_obj.options_dict['subject']['value']
    db = loris_getopt_obj.db

    imaging = Imaging(db, opt_verbose, loris_getopt_obj.config_info)
    try:
        create_visit = imaging.determine_subject_ids_from_name(opt_subject)['createVisitLabel']
    except DetermineSubjectException as exception:
        print(exception.message, file=sys.stderr)
        exit(lib.exitcode.CANDIDATE_MISMATCH)

    try:
        validate_subject_name(db, opt_verbose, opt_subject, create_visit)
        print(f'Validation successful for subject \'{opt_subject}\'.')
        exit(lib.exitcode.SUCCESS)
    except ValidateSubjectException as exception:
        print(exception.message, file=sys.stderr)
        exit(lib.exitcode.CANDIDATE_MISMATCH)


if __name__ == '__main__':
    main()

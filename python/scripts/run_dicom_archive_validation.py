#!/usr/bin/env python

"""Script to validate a DICOM archive from the filesystem against the one stored in the database"""

import os
import sys

from lib.dcm2bids_imaging_pipeline_lib.dicom_validation_pipeline import DicomValidationPipeline
from lib.lorisgetopt import LorisGetOpt

sys.path.append('/home/user/python')

# to limit the traceback when raising exceptions.
# sys.tracebacklimit = 0


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " DICOM ARCHIVE VALIDATOR\n"
        "********************************************************************\n\n"
        "The program does the following validations on a DICOM archive given as an argument:\n"
        "\t- Verify the PSC information using either PatientName or PatientID DICOM header\n"
        "\t- Verify/determine the ScannerID (optionally create a new one if necessary)\n"
        "\t- Verify the candidate IDs are valid\n"
        "\t- Verify the session is valid\n"
        "\t- Verify the DICOM archive against the checksum stored in the database\n"
        "\t- Update the mri_upload's 'isTarchiveValidated' field if above validations were successful\n\n"

        "usage  : dicom_archive_validation -p <profile> -t <tarchive_path> -u <upload_id>\n\n"

        "options: \n"
        "\t-p, --profile      : Name of the python database config file in config\n"
        "\t-t, --tarchive_path: Absolute path to the DICOM archive to validate\n"
        "\t-u, --upload_id    : ID of the upload (from mri_upload) associated with the DICOM archive to validate\n"
        "\t-v, --verbose      : If set, be verbose\n\n"

        "required options are: \n"
        "\t--profile\n"
        "\t--tarchive_path\n"
        "\t--upload_id\n\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "tarchive_path": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "t", "is_path": True
        },
        "upload_id": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "u", "is_path": False
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

    # validate the DICOM archive
    DicomValidationPipeline(loris_getopt_obj, os.path.basename(__file__[:-3]))


if __name__ == "__main__":
    main()

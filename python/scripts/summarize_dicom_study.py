#!/usr/bin/env python

import argparse
import sys
from dataclasses import dataclass

import lib.exitcode
from lib.import_dicom_study.summary_get import get_dicom_study_summary
from lib.import_dicom_study.summary_write import write_dicom_study_summary

parser = argparse.ArgumentParser(description=(
        'Read a DICOM directory and print the DICOM summary of this directory '
        'in the the console.'
    ))

parser.add_argument(
    'directory',
    help='The DICOM directory')

parser.add_argument(
    '--verbose',
    action='store_true',
    help='Set the script to be verbose')


@dataclass
class Args:
    directory: str
    verbose: bool


def main() -> None:
    parsed_args = parser.parse_args()
    args = Args(parsed_args.directory, parsed_args.verbose)

    try:
        summary = get_dicom_study_summary(args.directory, args.verbose)
    except Exception as e:
        print(
            (
                f"ERROR: Cannot create a summary for the directory '{args.directory}'.\n"
                f"Exception message:\n{e}"
            ),
            file=sys.stderr
        )
        exit(lib.exitcode.INVALID_DICOM)

    print(write_dicom_study_summary(summary))


if __name__ == "__main__":
    main()

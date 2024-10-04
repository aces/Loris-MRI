#!/usr/bin/env python

import argparse
from dataclasses import dataclass
import sys
import traceback

import lib.dicom.summary_make
import lib.dicom.summary_write
import lib.exitcode

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


def main():
    parsed_args = parser.parse_args()
    args = Args(parsed_args.directory, parsed_args.verbose)

    try:
        summary = lib.dicom.summary_make.make(args.directory, args.verbose)
    except Exception as e:
        print(f'ERROR: Cannot create a summary for the directory \'{args.directory}\'.', file=sys.stderr)
        print('Exception message:', file=sys.stderr)
        print(e, file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        exit(lib.exitcode.INVALID_DICOM)

    print(lib.dicom.summary_write.write_to_string(summary))


if __name__ == "__main__":
    main()

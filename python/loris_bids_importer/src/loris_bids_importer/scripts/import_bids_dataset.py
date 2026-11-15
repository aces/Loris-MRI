#!/usr/bin/env python

import argparse
from pathlib import Path

from lib.config_file import load_config
from lib.make_env import make_env

from loris_bids_importer.importer import BidsImporterArgs
from loris_bids_importer.main import import_bids_dataset


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Parse a BIDS dataset and insert it into LORIS.",
        allow_abbrev=False,
    )
    parser.add_argument('-p', '--profile',
        help="Name of the LORIS Python configuration file (default: config.py).")
    parser.add_argument('directory', type=Path,
        help="BIDS directory to import. If already within $data_dir/assembly_bids, no copy is performed.")
    parser.add_argument('-c', '--create-candidate', action='store_true',
        help="Create BIDS candidates in LORIS.")
    parser.add_argument('-s', '--create-session', action='store_true',
        help="Create BIDS sessions in LORIS.")
    parser.add_argument('-b', '--no-bids-validation', action='store_true',
        help="Disable validation for BIDS compliance.")
    parser.add_argument('-a', '--no-copy', action='store_true',
        help="Disable dataset copy into assembly_bids.")
    parser.add_argument('-t', '--type', choices=('raw', 'derivative'),
        help=("Dataset type. If omitted, look for both raw and derivative files. "
              "Required if no dataset_description.json is found."))
    parser.add_argument('-v', '--verbose', action='store_true', help="Print verbose progress information.")

    args = parser.parse_args()
    if not args.directory.is_dir():
        parser.error("Argument 'directory' must be an existing directory path.")
    return args


def pack_args(args: argparse.Namespace) -> BidsImporterArgs:
    return BidsImporterArgs(
        source_bids_path = args.directory,
        type             = args.type,
        bids_validation  = not args.no_bids_validation,
        create_candidate = args.create_candidate,
        create_session   = args.create_session,
        copy             = not args.no_copy,
        verbose          = args.verbose,
    )


def main() -> None:
    parsed_args = parse_args()
    config = load_config(parsed_args.profile)
    env = make_env('import-bids-dataset', parsed_args, config, parsed_args.verbose)
    args = pack_args(parsed_args)

    import_bids_dataset(env, args)

    print("Success !")


if __name__ == '__main__':
    main()

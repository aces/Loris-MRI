#!/usr/bin/env python

import argparse

import lib.exitcode
from lib.config_file import load_config
from lib.db.queries.physio_file import try_get_physio_file_with_id
from lib.env import Env
from lib.logging import log, log_error_exit, log_warning
from lib.make_env import make_env
from lib.physio.chunking import create_physio_channels_chunks


def main():
    parser = argparse.ArgumentParser(
        description="Run the electrophysiology chunking script on a range of electrophysiology files.",
    )

    parser.add_argument(
        '-p', '--profile',
        help="Name of the python database config file in the config directory."
    )

    parser.add_argument(
        '-s', '--smallest-id',
        type=int,
        required=True,
        help="Smallest electrophysiology file ID to chunk."
    )

    parser.add_argument(
        '-l', '--largest-id',
        type=int,
        required=True,
        help="Largest electrophysiology file ID to chunk."
    )

    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help="If set, be verbose."
    )

    args = parser.parse_args()

    config_file = load_config(args.profile)
    env = make_env('mass_electrophysiology_chunking', {}, config_file, args.verbose)

    if not (args.smallest_id <= args.largest_id):
        log_error_exit(
            env,
            "The --smallest-id value should be smaller than the --largest-id value",
            lib.exitcode.INVALID_ARG,
        )

    # Run the chunking script on electrophysiology files with an ID between the smallest and largest
    # IDs.
    for file_id in range(args.smallest_id, args.largest_id + 1):
        make_chunks(env, file_id)


def make_chunks(env: Env, physio_file_id: int):
    """
    Call the channel signal chunking script on the provided physiological file.
    """

    physio_file = try_get_physio_file_with_id(env.db, physio_file_id)
    if physio_file is None:
        log_warning(env, f"No physiological file for ID {physio_file_id} in the database, skipping.")
        return

    log(env, f"Chunking physiological file ID {physio_file.id}")
    create_physio_channels_chunks(env, physio_file)


if __name__ == '__main__':
    main()

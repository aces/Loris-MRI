#!/usr/bin/env python

import argparse
from pathlib import Path

from loris_bids_utils.meg.ctf.copy_ds import copy_bids_meg_ctf_ds


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Copy and rename a BIDS MEG CTF .ds dataset, updating its "
            "BIDS-derived metadata and internal CTF references in the process."
        )
    )

    parser.add_argument(
        'source',
        type=Path,
        help="Source BIDS CTF .ds path",
    )

    parser.add_argument(
        'destination',
        type=Path,
        help="Destination .ds path or parent directory path",
    )

    args = parser.parse_args()

    source_path: Path = args.source
    destination_path: Path = args.destination

    if destination_path.suffix != ".ds":
        destination_path = destination_path / source_path.name

    unknown_paths = copy_bids_meg_ctf_ds(source_path, destination_path)

    print(f"Created: {destination_path}")

    if unknown_paths:
        print("Unknown files:")
        for unknown_path in unknown_paths:
            print(f"  {unknown_path}")


if __name__ == '__main__':
    main()

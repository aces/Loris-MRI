#!/usr/bin/env python

import argparse
import sys
from pathlib import Path
from typing import cast

import mne.io
from mne.io.ctf import RawCTF

from loris_eeg_chunker.chunking import write_chunk_directory  # type: ignore


def load_channels(path: Path) -> RawCTF:
    return mne.io.read_raw_ctf(path, preload=False, verbose=False)    # type: ignore


def main():
    parser = argparse.ArgumentParser(
        description="Convert CTF MEG files (.ds directories) to chunks for browser based visualisation.")
    parser.add_argument('files', metavar='FILE', type=Path, nargs='+',
                        help="one or more CTF .ds directories to convert to a directory of chunks")
    parser.add_argument('--channel-index', '-i', type=int, default=0,
                        help="Starting index of the channels to process")
    parser.add_argument('--channel-count', '-c', type=int,
                        help="Number of channels to process")
    parser.add_argument('--chunk-size', '-s', type=int, default=5000,
                        help="1 dimensional chunk size")
    parser.add_argument('--downsamplings', '-r', type=int,
                        help="How many downsampling levels to write to disk starting from the coarsest level.")
    parser.add_argument('--destination', '-d', type=Path,
                        help="optional destination for all the chunk directories")
    parser.add_argument('--prefix', '-p', type=str,
                        help="optional prefixing parent folder name each directory of chunks gets placed under")

    args = parser.parse_args()

    for path in args.files:
        raw_ctf = mne.io.read_raw_ctf(path, preload=False, verbose=False)  # type: ignore
        channel_names = cast(list[str], raw_ctf.ch_names)  # type: ignore

        if args.channel_index < 0:
            print("Channel index must be a positive integer", file=sys.stderr)
            sys.exit(-1)

        if args.channel_index >= len(channel_names):
            print("Channel index exceeds the number of channels", file=sys.stderr)
            sys.exit(-1)

        if args.channel_count and args.channel_count < 0:
            print("Channel count must be a positive integer", file=sys.stderr)
            sys.exit(-1)

        print(f'Creating chunks for {path}')
        write_chunk_directory(
            path=path,
            from_channel_index=args.channel_index,
            from_channel_name=channel_names[args.channel_index],  # type: ignore
            channel_count=args.channel_count,
            loader=load_channels,
            chunk_size=args.chunk_size,
            destination=args.destination,
            prefix=args.prefix
        )


if __name__ == '__main__':
    main()

#!/usr/bin/env python

import argparse
import sys
from pathlib import Path

import mne.io
from mne.io.edf.edf import RawEDF

from loris_ephys_chunker.chunking import write_chunk_directory


def load_channels(path: Path) -> RawEDF:
    return mne.io.read_raw_edf(path, preload=False)  # type: ignore


def main():
    parser = argparse.ArgumentParser(
        description='Convert .edf files to chunks for browser based visualization.')
    parser.add_argument('files', metavar='FILE', type=Path, nargs='+',
                        help='one or more .edf files to convert to a directory of chunks next to the input file')
    parser.add_argument('--channel_index', '-i', dest='channel_index', type=int, default=0,
                        help='Starting index of the channels to process')
    parser.add_argument('--channel_count', '-c', dest='channel_count', type=int,
                        help='Number of channels to process')
    parser.add_argument('--chunk-size', '-s', dest='chunk_size', type=int, default=5000,
                        help='1 dimensional chunk size')
    parser.add_argument('--downsamplings', '-r', dest='downsamplings', type=int,
                        help='How many downsampling levels to write to disk starting from the coarsest level.')
    parser.add_argument('--destination', '-d', dest='destination', type=Path,
                        help='optional destination for all the chunk directories')
    parser.add_argument('--prefix', '-p', dest="prefix", type=str,
                        help='optional prefixing parent folder name each directory of chunks gets placed under')

    args = parser.parse_args()
    for path in args.files:
        raw_edf = load_channels(path)
        channel_names = raw_edf.ch_names

        if args.channel_index < 0:
            sys.exit("Channel index must be a positive integer")

        if args.channel_index >= len(channel_names):
            sys.exit("Channel index exceeds the number of channels")

        if args.channel_count and args.channel_count < 0:
            sys.exit("Channel count must be a positive integer")

        channel_count = args.channel_count
        if channel_count is None:
            channel_count = len(channel_names) - args.channel_index
        channel_count = min(channel_count, len(channel_names) - args.channel_index)

        requested_channel_indices = range(args.channel_index, args.channel_index + channel_count)
        channel_indices = [
            channel_index
            for channel_index in requested_channel_indices
            if raw_edf.get_channel_types(picks=[channel_index])[0] != 'stim'  # type: ignore
        ]
        if not channel_indices:
            continue

        print(f'Creating chunks for {path}')
        write_chunk_directory(
            path=path,
            raw=raw_edf,
            channel_indices=channel_indices,
            chunk_size=args.chunk_size,
            downsamplings=args.downsamplings,
            destination=args.destination,
            prefix=args.prefix
        )


if __name__ == '__main__':
    main()

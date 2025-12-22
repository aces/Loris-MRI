#!/usr/bin/env python

import argparse
import sys
from pathlib import Path
from typing import cast

from mne.io import read_raw_ctf  # type: ignore
from mne.io.ctf import RawCTF

from loris_eeg_chunker.chunking import write_chunk_directory  # type: ignore


def load_channels(path: Path) -> RawCTF:
    """Load CTF MEG data using MNE."""
    # Load raw CTF data
    raw_ctf = read_raw_ctf(path, preload=False, verbose=False)

    # CTF data typically has triggers/stim channels that we might want to exclude
    # You can modify this based on your needs
    return raw_ctf


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
        # Check if it's a CTF .ds directory
        if not path.is_dir() or path.suffix != '.ds':
            print(f"Warning: {path} doesn't appear to be a CTF .ds directory. Skipping.")
            continue

        # Load the raw_ctf data to get channel information
        try:
            raw_ctf = read_raw_ctf(path, preload=False, verbose=False)
        except Exception as e:
            print(f"Error loading {path}: {e}")
            continue

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

# Channel filtering code, keep here for now decided if needed or not later:
#
#     parser.add_argument('--exclude-ref', action='store_true',
#                         help="exclude reference channels")
#     parser.add_argument('--meg-only', action='store_true',
#                         help="only process MEG channels (exclude EEG, EOG, etc.)")
#     parser.add_argument('--grad-only', action='store_true',
#                         help="only process gradiometer channels")
#     parser.add_argument('--mag-only', action='store_true',
#                         help="only process magnetometer channels")
#
#     ...
#
#         # Get all channel names
#         all_channel_names = cast(list[str], raw_ctf.ch_names)  # type: ignore
#
#         # Filter channels based on arguments
#         filtered_channel_names: list[str] = []
#
#         for idx, ch_name in enumerate(all_channel_names):
#             ch_type = raw_ctf.get_channel_types()[idx]  # type: ignore
#
#             # Apply filters
#             if args.meg_only and ch_type not in ['mag', 'grad']:
#                 continue
#             if args.grad_only and ch_type != 'grad':
#                 continue
#             if args.mag_only and ch_type != 'mag':
#                 continue
#             if args.exclude_ref and 'REF' in ch_name.upper():
#                 continue
#
#             filtered_channel_names.append(ch_name)
#
#         # If we filtered channels, we need to update the indices
#         if filtered_channel_names != all_channel_names:
#             # Create a mapping from filtered to original indices
#             original_to_filtered = {}
#             filtered_idx = 0
#             for orig_idx, ch_name in enumerate(all_channel_names):
#                 if ch_name in filtered_channel_names:
#                     original_to_filtered[orig_idx] = filtered_idx
#                     filtered_idx += 1
#
#             # Adjust channel_index if needed
#             if args.channel_index >= len(all_channel_names):
#                 print("Channel index exceeds the number of channels")
#                 sys.exit(-1)
#
#             # If the requested channel was filtered out, find the next available
#             start_channel_name = all_channel_names[args.channel_index]
#             if start_channel_name not in filtered_channel_names:
#                 # Find the first channel after the requested index that's in filtered list
#                 for i in range(args.channel_index + 1, len(all_channel_names)):
#                     if all_channel_names[i] in filtered_channel_names:
#                         args.channel_index = i
#                         start_channel_name = all_channel_names[i]
#                         print(f"Note: Requested channel was filtered out. Using {start_channel_name} instead.")
#                         break
#                 else:
#                     print("No channels available after applying filters", file=sys.stderr)
#                     sys.exit(-1)
#
#         channel_names = filtered_channel_names if filtered_channel_names else all_channel_names

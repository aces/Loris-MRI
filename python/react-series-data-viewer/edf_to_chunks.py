import argparse

import mne.io
import numpy as np

from chunking import *

def load_channels(path):
    return mne.io.read_raw_edf(path, preload=False)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Convert .edf files to chunks for browser based visualisation.')
    parser.add_argument('files', metavar='FILE', type=str, nargs='+',
                        help='one or more .edf files to convert to a directory of chunks next to the input file')
    parser.add_argument('--chunk-size', '-s', dest='chunk_size', type=int, default=5000,
                        help='1 dimensional chunk size')
    parser.add_argument('--downsamplings', '-r', dest='downsamplings', type=int,
                        help='How many downsampling levels to write to disk starting from the coarsest level.')
    parser.add_argument('--destination', '-d', dest='destination', type=str,
                        help='optional destination for all the chunk directories')
    parser.add_argument('--prefix', '-p', dest="prefix", type=str,
                        help='optional prefixing parent folder name each directory of chunks gets placed under')

    args = parser.parse_args()
    for path in args.files:
        write_chunk_directory(
            path=path,
            loader=load_channels,
            chunk_size=args.chunk_size,
            destination=args.destination,
            prefix=args.prefix
        )

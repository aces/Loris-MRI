import argparse
import mne.io
import mne.io.edf.edf as mne_edf
from chunking import write_chunk_directory
import sys

def load_channels(exclude):
    return lambda path : mne.io.read_raw_edf(path, exclude=exclude, preload=False)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Convert .edf files to chunks for browser based visualisation.')
    parser.add_argument('files', metavar='FILE', type=str, nargs='+',
                        help='one or more .edf files to convert to a directory of chunks next to the input file')
    parser.add_argument('--channel_index', '-i', dest='channel_index', type=int, default=0,
                        help='Starting index of the channels to process')
    parser.add_argument('--channel_count', '-c', dest='channel_count', type=int,
                        help='Number of channels to process')
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
        _, edf_info, _ = mne_edf._get_info(path, stim_channel='auto', eog=None, misc=None, exclude=(), preload=False)
        channel_names = edf_info['ch_names']

        if args.channel_index < 0:
            sys.exit("Channel index must be a positive integer")

        if args.channel_index >= len(channel_names):
            sys.exit("Channel index exceeds the number of channels")

        if args.channel_count and args.channel_count < 0:
            sys.exit("Channel count must be a positive integer")

        if args.channel_index in edf_info['stim_channel_idxs']:
            continue

        if not args.channel_count:
            args.channel_count = len(channel_names) - args.channel_index

        for i in range(args.channel_count):
            channel_index = args.channel_index + i

            # check if channel_index is a stim channel
            # to avoid a bug in mne.io.edf.edf
            # (see issue https://github.com/mne-tools/mne-python/issues/9811) 
            stim_channel_idxs, _ = mne_edf._check_stim_channel(
                'auto', [channel_names[channel_index]]
            )
            if len(stim_channel_idxs) == 1:
                continue

            # excluding channels in the loader reduce the time required to read the file
            # and avoid memory issues
            # we only load the channel at index channel_index+i
            exclude = channel_names[:channel_index] + channel_names[channel_index + 1:]
            write_chunk_directory(
                path=path,
                loader=load_channels(exclude),
                from_channel_index=channel_index,
                from_channel_name=channel_names[channel_index],
                channel_count=1,
                chunk_size=args.chunk_size,
                destination=args.destination,
                prefix=args.prefix
            )

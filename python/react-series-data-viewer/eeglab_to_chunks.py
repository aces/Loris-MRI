import argparse
import mne.io
import mne.io.eeglab.eeglab as mne_eeglab
import chunking
import sys


def load_channels(path):
    return mne.io.read_raw_eeglab(path, preload=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Convert .set files to chunks for browser based visualisation.')
    parser.add_argument('files', metavar='FILE', type=str, nargs='+',
                        help='one or more .set files to convert to a directory of chunks next to the input file')
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
        eeg = mne_eeglab._check_load_mat(path, None)
        eeglab_info = mne_eeglab._get_info(eeg, eog=())
        channel_names = eeglab_info[0]['ch_names']

        if args.channel_index < 0:
            sys.exit("Channel index must be a positive integer")

        if args.channel_index >= len(channel_names):
            sys.exit("Channel index exceeds the number of channels")

        if args.channel_count and args.channel_count < 0:
            sys.exit("Channel count must be a positive integer")

        print('Creating chunks for {}'.format(path))
        chunking.write_chunk_directory(
            path=path,
            from_channel_index=args.channel_index,
            from_channel_name=channel_names[args.channel_index],
            channel_count=args.channel_count,
            loader=load_channels,
            chunk_size=args.chunk_size,
            destination=args.destination,
            prefix=args.prefix
        )

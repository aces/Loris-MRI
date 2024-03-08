import errno
import json
import math
import os
from collections import OrderedDict
import numpy as np
from scipy import signal
import sys

from protocol_buffers import chunk_pb2 as chunk_pb


def pad_channels(channels, chunk_size):
    num_chunks = math.ceil(channels.shape[-1] / chunk_size)
    total_chunked_points = num_chunks * chunk_size
    padding = total_chunked_points - channels.shape[-1]
    padding_seq = [(0, 0) for _ in channels.shape]
    padding_seq[-1] = (0, padding)
    padded_channels = np.pad(channels, padding_seq, 'edge')
    return padded_channels


def channels_to_chunks(channels, chunk_size):
    padded_channels = pad_channels(channels, chunk_size)
    padded_channels = np.expand_dims(padded_channels, axis=-2)
    shape = list(padded_channels.shape)
    shape[-2] = int(shape[-1] / chunk_size)
    shape[-1] = chunk_size
    shape = tuple(shape)
    padded_channels = padded_channels.reshape(shape)
    return padded_channels


def create_chunks_from_channels_list(channels_list, chunk_size):
    channel_chunks_list = [
        channels_to_chunks(channels, chunk_size)
        for channels in channels_list
    ]
    return channel_chunks_list


def downsample_channel(channel, chunk_size, downsampling):
    if downsampling == 0:
        return channel
    down = chunk_size**downsampling
    downsampled_size = channel.shape[-1] / down
    if downsampled_size <= chunk_size * 2:
        downsampled_size = chunk_size * 2
        down = math.floor(channel.shape[-1] / (chunk_size * 2))
    return signal.resample(channel, downsampled_size, axis=-1)


def create_downsampled_channels_list(channel, chunk_size):
    downsamplings = math.ceil(math.log(channel.shape[-1]) / math.log(chunk_size))
    downsamplings = range(downsamplings - 1, -1, -1)
    downsampled_channels = [
        downsample_channel(channel, chunk_size, downsampling)
        for downsampling in downsamplings
    ]
    sizes = set()
    unique_sized = []
    for channel in downsampled_channels:
        if channel.shape[-1] in sizes:
            continue
        unique_sized.append(channel)
        sizes.add(channel.shape[-1])
    return unique_sized


def chunk_dir_path(input_path, prefix=None, destination=None):
    base_path, _ = os.path.splitext(input_path)
    root, chunk_dir_name = os.path.split(base_path)
    root = root if destination is None else destination
    prefix = '' if prefix is None else prefix
    chunk_dir = os.path.join(root, prefix, chunk_dir_name)
    return chunk_dir + '.chunks'


def create_path_dirs(path):
    try:
        os.makedirs(path)
    except OSError as e:
        if e.errno != errno.EEXIST:
            raise


def write_index_json(
    chunk_dir,
    time_interval,
    series_range,
    from_channel_index,
    channel_count,
    channel_names,
    channel_ranges,
    chunk_size,
    downsamplings,
    channel_chunks_list,
    trace_types={}
):
    json_dict = OrderedDict([
        ('timeInterval', list(time_interval)),
        ('seriesRange', series_range),
        ('chunkSize', chunk_size),
        ('downsamplings', list(downsamplings)),
        ('shapes', [
            list(downsampled.shape)
            for downsampled in channel_chunks_list
        ]),
        ('traceTypes', trace_types),
        ('channelMetadata', [
            {
                'name': channel_names[i],
                'seriesRange': channel_ranges[i],
                'index': from_channel_index + i
            }
            for i in range(len(channel_ranges))
        ])
    ])
    create_path_dirs(chunk_dir)
    
    data = None
    try:
        with open(os.path.join(chunk_dir, 'index.json'), 'r+') as index_json:
            data = json.load(index_json)
            if json_dict['chunkSize'] != data['chunkSize']:
                sys.exit("Chunk size does not match the one found in index.json.")

            if json_dict['downsamplings'] != data['downsamplings']:
                sys.exit("Downsamplings does not match the one found in index.json.")

            indices = [channelMetadata['index'] for channelMetadata in json_dict['channelMetadata']]
            json_dict['channelMetadata'].extend(
                channelMetadata for channelMetadata in data['channelMetadata']
                if channelMetadata['index'] not in indices
            )
            json_dict['channelMetadata'] = sorted(json_dict['channelMetadata'], key=lambda k: k['index'])
            if data['seriesRange'][0] < json_dict['seriesRange'][0]:
                json_dict['seriesRange'][0] = data['seriesRange'][0]

            if data['seriesRange'][1] > json_dict['seriesRange'][1]:
                json_dict['seriesRange'][1] = data['seriesRange'][1]
    except Exception as e:
        print(e)
        print('Unable to read an existing index.json file. A new one will be created.')

    with open(os.path.join(chunk_dir, 'index.json'), 'w+') as index_json:
        json.dump(json_dict, index_json, indent=2, separators=(',', ': '))


def encode_chunk(chunk, index, downsampling):
    encoded = chunk_pb.FloatChunk(
        index=index, downsampling=downsampling, cutoff=len(chunk),  samples=chunk)
    return encoded.SerializeToString()


def write_chunks(chunk_dir, channel_chunks_list, channel_index):
    for downsampling, channels in enumerate(channel_chunks_list):
        for channel_offset, channel in enumerate(channels):
            for trace_index, trace in enumerate(channel):
                trace_path = os.path.join(
                    chunk_dir,
                    'raw',
                    str(downsampling),
                    str(channel_index + channel_offset),
                    str(trace_index)
                )
                create_path_dirs(trace_path)
                for chunk_index, chunk in enumerate(trace):
                    chunk_path = os.path.join(
                        trace_path, str(chunk_index)) + '.buf'
                    encoded_chunk = encode_chunk(
                        chunk, chunk_index, downsampling)
                    with open(chunk_path, 'w+b') as chunk_file:
                        chunk_file.write(encoded_chunk)


def mne_file_to_chunks(path, chunk_size, loader, from_channel_name, channel_count):
    parsed = loader(path)
    time_interval = (parsed.times[0], parsed.times[-1])
    channel_names = parsed.info["ch_names"]
    channel_ranges = []
    signal_range = [np.PINF, np.NINF]
    channel_chunks_list = []

    if from_channel_name:
        from_channel_index = channel_names.index(from_channel_name)
        if channel_count and from_channel_index + channel_count < len(channel_names):
            selected_channels = channel_names[from_channel_index:from_channel_index + channel_count]
        else:
            selected_channels = channel_names[from_channel_index:]

    for i, channel_name in enumerate(selected_channels):
        print("Processing channel " + channel_name)
        channel = parsed.get_data(channel_name)
        channel_min = np.amin(channel)
        channel_max = np.amax(channel)
        channel_ranges.append((channel_min, channel_max))
        signal_range = [min(channel_min, signal_range[0]), max(channel_max, signal_range[1])]

        channel = np.expand_dims(channel, axis=-2)
        downsampled_channels = create_downsampled_channels_list(channel, chunk_size)
        chunks = create_chunks_from_channels_list(downsampled_channels, chunk_size)
        if not channel_chunks_list:
            channel_chunks_list = chunks
        else:
            for j, chunk in enumerate(chunks):
                channel_chunks_list[j] = np.append(channel_chunks_list[j], chunk, axis=0)

    return channel_chunks_list, time_interval, signal_range, channel_names, channel_ranges


def write_chunk_directory(path, chunk_size, loader, from_channel_index=0, from_channel_name=None, 
                          channel_count=None, downsamplings=None, prefix=None, destination=None):

    chunk_dir = chunk_dir_path(path, prefix=prefix, destination=destination)
    channel_chunks_list, time_interval, signal_range, channel_names, channel_ranges = mne_file_to_chunks(
        path, chunk_size, loader, from_channel_name, channel_count
    )
    if downsamplings is not None:
        channel_chunks_list = channel_chunks_list[:downsamplings]
    write_index_json(
        chunk_dir,
        time_interval,
        signal_range,
        from_channel_index,
        channel_count,
        channel_names,
        channel_ranges,
        chunk_size,
        range(len(channel_chunks_list)),
        channel_chunks_list
    )
    write_chunks(chunk_dir, channel_chunks_list, from_channel_index)

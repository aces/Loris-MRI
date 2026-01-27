import json
import math
import sys
from collections import OrderedDict
from collections.abc import Callable
from pathlib import Path
from typing import Any, cast

import numpy as np
import numpy.typing as npt
from mne.io import BaseRaw
from scipy import signal

from loris_eeg_chunker.protocol_buffers import chunk_pb2 as chunk_pb

ChannelArray = npt.NDArray[np.float64]


def pad_values(values: ChannelArray, chunk_size: int) -> ChannelArray:
    num_chunks = math.ceil(values.shape[-1] / chunk_size)
    total_chunked_points = num_chunks * chunk_size
    padding = total_chunked_points - values.shape[-1]
    padding_seq = [(0, 0) for _ in values.shape]
    padding_seq[-1] = (0, padding)
    padded_values = np.pad(values, padding_seq, 'edge')
    return padded_values


def values_to_chunks(values: ChannelArray, chunk_size: int) -> ChannelArray:
    padded_values = pad_values(values, chunk_size)
    padded_values = np.expand_dims(padded_values, axis=-2)
    shape = list(padded_values.shape)
    shape[-2] = int(shape[-1] / chunk_size)         # # of chunks
    shape[-1] = chunk_size                          # # of samples per chunk
    shape = tuple(shape)
    padded_values = padded_values.reshape(shape)
    return padded_values


def create_chunks_from_values_lists(values_lists: list[ChannelArray], chunk_size: int) -> list[ChannelArray]:
    chunks_lists = [
        values_to_chunks(values, chunk_size)
        for values in values_lists
    ]
    return chunks_lists


def downsample_channel(channel: ChannelArray, chunk_size: int, downsampling: int) -> ChannelArray:
    if downsampling == 0:
        return channel
    down = chunk_size**downsampling
    downsampled_size = channel.shape[-1] / down
    if downsampled_size <= chunk_size * 2:
        downsampled_size = chunk_size * 2
    return signal.resample(channel, downsampled_size, axis=-1)  # type: ignore


def create_downsampled_values_lists(channel: ChannelArray, chunk_size: int) -> list[ChannelArray]:
    downsamplings = math.ceil(math.log(channel.shape[-1]) / math.log(chunk_size))
    downsamplings = range(downsamplings - 1, -1, -1)
    downsampled_channels = [
        downsample_channel(channel, chunk_size, downsampling)
        for downsampling in downsamplings
    ]
    sizes: set[int] = set()
    unique_sized: list[ChannelArray] = []
    for channel in downsampled_channels:
        if channel.shape[-1] in sizes:
            continue
        unique_sized.append(channel)
        sizes.add(channel.shape[-1])
    return unique_sized


def chunk_dir_path(input_path: Path, prefix: str | None = None, destination: Path | None = None) -> Path:
    root = input_path.parent if destination is None else destination
    prefix = '' if prefix is None else prefix
    return (root / prefix / f'{input_path.stem}.chunks')


def write_index_json(
    chunk_dir: Path,
    time_interval: tuple[np.float64, np.float64],
    series_range: tuple[float, float],
    channel_metadata: list[dict[str, Any]],
    chunk_size: int,
    downsamplings: list[int],
    valid_samples_in_last_chunk: list[int],
    shapes: list[list[int]],
    trace_types: dict[Any, Any] = {},
):
    chunk_dir.mkdir(parents=True, exist_ok=True)

    data = None
    try:
        with open(chunk_dir / 'index.json', 'r+') as index_json:
            data = json.load(index_json)
            if chunk_size != data['chunkSize']:
                sys.exit("Chunk size does not match the one found in index.json.")

            if downsamplings != data['downsamplings']:
                sys.exit("Downsamplings does not match the one found in index.json.")

            indices = [channelMetadata['index'] for channelMetadata in channel_metadata]
            channel_metadata.extend(
                channelMetadata for channelMetadata in data['channelMetadata']
                if channelMetadata['index'] not in indices
            )
            channel_metadata = sorted(channel_metadata, key=lambda k: k['index'])
            if data['seriesRange'][0] < series_range[0]:
                series_range = (data['seriesRange'][0], series_range[1])

            if data['seriesRange'][1] > series_range[1]:
                series_range = (series_range[0], data['seriesRange'][1])
    except Exception as e:
        print(e)
        print('Unable to read an existing index.json file. A new one will be created.')

    json_dict = OrderedDict([
        ('timeInterval', list(time_interval)),
        ('seriesRange', series_range),
        ('chunkSize', chunk_size),
        ('validSamples', valid_samples_in_last_chunk),
        ('downsamplings', downsamplings),
        ('shapes', shapes),
        ('traceTypes', trace_types),
        ('channelMetadata', channel_metadata)
    ])

    with open(chunk_dir / 'index.json', 'w+') as index_json:
        json.dump(json_dict, index_json, indent=2)


def encode_chunk(chunk: ChannelArray, index: int, downsampling: int) -> bytes:
    encoded = chunk_pb.FloatChunk(  # type: ignore
        index=index, downsampling=downsampling, cutoff=len(chunk), samples=chunk
    )
    return encoded.SerializeToString()  # type: ignore


def write_chunks(chunk_dir: Path, channel_chunks_list: list[ChannelArray], channel_index: int):
    for downsampling, channels in enumerate(channel_chunks_list):
        for channel_offset, channel in enumerate(channels):
            for trace_index, trace in enumerate(channel):
                trace_path = (
                    chunk_dir
                    / 'raw'
                    / str(downsampling)
                    / str(channel_index + channel_offset)
                    / str(trace_index)
                )

                trace_path.mkdir(parents=True)
                for chunk_index, chunk in enumerate(trace):
                    encoded_chunk = encode_chunk(chunk, chunk_index, downsampling)
                    with open(trace_path / f'{chunk_index}.buf', 'w+b') as chunk_file:
                        chunk_file.write(encoded_chunk)


def mne_file_to_chunks(
    path: Path,
    chunk_size: int,
    loader: Callable[[Path], BaseRaw],
    from_channel_name: str | None,
    channel_count: int | None,
) -> tuple[
    list[ChannelArray],
    tuple[np.float64, np.float64],
    tuple[float, float],
    list[str],
    list[tuple[float, float]],
    list[int],
]:
    parsed = loader(path)
    time_interval: tuple[np.float64, np.float64] = (parsed.times[0], parsed.times[-1])
    channel_names = cast(list[str], parsed.info["ch_names"])
    channel_ranges: list[tuple[float, float]] = []
    signal_range = (np.inf, -np.inf)
    channel_chunks_list = []
    selected_channels = []
    valid_samples_in_last_chunk = []

    if from_channel_name:
        from_channel_index = channel_names.index(from_channel_name)
        if channel_count and from_channel_index + channel_count < len(channel_names):
            selected_channels = channel_names[from_channel_index:from_channel_index + channel_count]
        else:
            selected_channels = channel_names[from_channel_index:]

    for i, channel_name in enumerate(selected_channels, start=1):
        print(f"Processing channel {channel_name} ({i} / {len(selected_channels)})")
        channel = cast(ChannelArray, parsed.get_data(channel_name))  # type: ignore
        channel_min = np.amin(channel)
        channel_max = np.amax(channel)
        channel_ranges.append((channel_min, channel_max))
        signal_range = (min(channel_min, signal_range[0]), max(channel_max, signal_range[1]))

        channel = np.expand_dims(channel, axis=-2)
        downsampled_values_lists = create_downsampled_values_lists(channel, chunk_size)
        chunks = create_chunks_from_values_lists(downsampled_values_lists, chunk_size)

        if not channel_chunks_list:
            channel_chunks_list = chunks
            # Assuming all channels have the same recording length as first channel
            valid_samples_in_last_chunk = [
                num_values % chunk_size or chunk_size   # chunk size if 0
                for num_values in map(lambda values: len(values[0][0]), downsampled_values_lists)
            ]
        else:
            for j, chunk in enumerate(chunks):
                channel_chunks_list[j] = np.append(channel_chunks_list[j], chunk, axis=0)

    return channel_chunks_list, time_interval, signal_range, channel_names, channel_ranges, valid_samples_in_last_chunk


def write_chunk_directory(
    path: Path,
    chunk_size: int,
    loader: Callable[[Path], BaseRaw],
    from_channel_index: int = 0,
    from_channel_name: str | None = None,
    channel_count: int | None = None,
    downsamplings: int | None = None,
    prefix: str | None = None,
    destination: Path | None = None,
):
    chunk_dir = chunk_dir_path(path, prefix=prefix, destination=destination)
    channel_chunks_list, time_interval, signal_range, \
        channel_names, channel_ranges, valid_samples_in_last_chunk = \
        mne_file_to_chunks(path, chunk_size, loader, from_channel_name, channel_count)

    if downsamplings is not None:
        channel_chunks_list = channel_chunks_list[:downsamplings]

    channel_metadata = [
        {
            'name': channel_names[i],
            'seriesRange': channel_ranges[i],
            'index': from_channel_index + i
        }
        for i in range(len(channel_ranges))
    ]

    write_index_json(
        chunk_dir,
        time_interval,
        signal_range,
        channel_metadata,
        chunk_size,
        valid_samples_in_last_chunk,
        list(range(len(channel_chunks_list))),
        [list(downsampled.shape) for downsampled in channel_chunks_list]
    )
    write_chunks(chunk_dir, channel_chunks_list, from_channel_index)

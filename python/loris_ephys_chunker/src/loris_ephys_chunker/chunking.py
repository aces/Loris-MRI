import json
import math
import sys
from collections import OrderedDict
from pathlib import Path
from typing import Any, cast

import numpy as np
import numpy.typing as npt
from mne.io import BaseRaw
from scipy import signal

from loris_ephys_chunker.protocol_buffers import chunk_pb2 as chunk_pb

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

    sample_count = channel.shape[-1]
    requested_factor = chunk_size**downsampling
    target_size = max(math.ceil(sample_count / requested_factor), chunk_size * 2)

    # Keep the FIR filter reasonably sized even when the input and target lengths are relatively
    # prime. Rounding down guarantees at least target_size output samples; chunk padding handles
    # the small excess.
    effective_factor = max(1, sample_count // target_size)
    if effective_factor == 1:
        return channel

    # FFT resampling treats the recording as periodic and rings where the final and first samples
    # are implicitly joined. Polyphase FIR resampling avoids that wraparound, while linear boundary
    # extension prevents zero/constant padding from introducing a new endpoint discontinuity.
    return signal.resample_poly(  # type: ignore
        channel,
        up=1,
        down=effective_factor,
        axis=-1,
        padtype='line',
    )


def create_downsampled_values_lists(
    channel: ChannelArray,
    chunk_size: int,
    downsamplings: int | None = None,
) -> list[ChannelArray]:
    if downsamplings is not None and downsamplings <= 0:
        return []

    downsampling_count = math.ceil(math.log(channel.shape[-1]) / math.log(chunk_size))
    downsampling_levels = range(downsampling_count - 1, -1, -1)
    sizes: set[int] = set()
    unique_sized: list[ChannelArray] = []
    for downsampling_level in downsampling_levels:
        downsampled_channel = downsample_channel(channel, chunk_size, downsampling_level)
        if downsampled_channel.shape[-1] in sizes:
            continue
        unique_sized.append(downsampled_channel)
        sizes.add(downsampled_channel.shape[-1])
        if downsamplings is not None and len(unique_sized) >= downsamplings:
            break
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

            indices = [channel_metadata_entry['index'] for channel_metadata_entry in channel_metadata]
            channel_metadata.extend(
                channel_metadata_entry for channel_metadata_entry in data['channelMetadata']
                if channel_metadata_entry['index'] not in indices
            )
            channel_metadata = sorted(channel_metadata, key=lambda k: k['index'])
            for shape in shapes:
                shape[0] = len(channel_metadata)
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

                trace_path.mkdir(parents=True, exist_ok=True)
                for chunk_index, chunk in enumerate(trace):
                    encoded_chunk = encode_chunk(chunk, chunk_index, downsampling)
                    with open(trace_path / f'{chunk_index}.buf', 'w+b') as chunk_file:
                        chunk_file.write(encoded_chunk)


def write_mne_channels(
    chunk_dir: Path,
    chunk_size: int,
    raw: BaseRaw,
    from_channel_index: int,
    from_channel_name: str | None,
    channel_count: int | None,
    downsamplings: int | None,
    channel_indices: list[int] | None,
) -> tuple[
    tuple[np.float64, np.float64],
    tuple[float, float],
    list[str],
    list[int],
    list[tuple[float, float]],
    list[int],
    list[list[int]],
]:
    """Read and write selected channels while retaining only one channel's data in memory."""
    time_interval: tuple[np.float64, np.float64] = (raw.times[0], raw.times[-1])
    channel_names = cast(list[str], raw.info["ch_names"])
    channel_ranges: list[tuple[float, float]] = []
    signal_range = (np.inf, -np.inf)
    valid_samples_in_last_chunk: list[int] = []
    shapes: list[list[int]] = []

    if channel_indices is not None:
        selected_channel_indices = channel_indices
    elif from_channel_name is not None:
        from_channel_index = channel_names.index(from_channel_name)
        if channel_count is not None:
            selected_channel_indices = list(range(
                from_channel_index,
                min(from_channel_index + channel_count, len(channel_names)),
            ))
        else:
            selected_channel_indices = list(range(from_channel_index, len(channel_names)))
    else:
        selected_channel_indices = list(range(len(channel_names)))
    selected_channels = [channel_names[index] for index in selected_channel_indices]

    for i, (channel_index, channel_name) in enumerate(
        zip(selected_channel_indices, selected_channels, strict=True),
        start=1,
    ):
        print(f"Processing channel {channel_name} ({i} / {len(selected_channels)})")
        channel = cast(ChannelArray, raw.get_data(channel_name))  # type: ignore
        channel_min = np.amin(channel)
        channel_max = np.amax(channel)
        channel_ranges.append((channel_min, channel_max))
        signal_range = (min(channel_min, signal_range[0]), max(channel_max, signal_range[1]))

        channel = np.expand_dims(channel, axis=-2)
        downsampled_values_lists = create_downsampled_values_lists(channel, chunk_size, downsamplings)
        chunks = create_chunks_from_values_lists(downsampled_values_lists, chunk_size)

        if not shapes:
            shapes = [
                [len(selected_channels), *downsampled_chunks.shape[1:]]
                for downsampled_chunks in chunks
            ]
            # Assuming all channels have the same recording length as first channel
            valid_samples_in_last_chunk = [
                num_values % chunk_size or chunk_size   # chunk size if 0
                for num_values in map(lambda values: len(values[0][0]), downsampled_values_lists)
            ]
        write_chunks(chunk_dir, chunks, channel_index)

    return (
        time_interval,
        signal_range,
        selected_channels,
        selected_channel_indices,
        channel_ranges,
        valid_samples_in_last_chunk,
        shapes,
    )


def write_chunk_directory(
    path: Path,
    raw: BaseRaw,
    chunk_size: int,
    from_channel_index: int = 0,
    from_channel_name: str | None = None,
    channel_count: int | None = None,
    downsamplings: int | None = None,
    prefix: str | None = None,
    destination: Path | None = None,
    channel_indices: list[int] | None = None,
):
    chunk_dir = chunk_dir_path(path, prefix=prefix, destination=destination)
    time_interval, signal_range, channel_names, selected_channel_indices, channel_ranges, \
        valid_samples_in_last_chunk, shapes = write_mne_channels(
            chunk_dir,
            chunk_size,
            raw,
            from_channel_index,
            from_channel_name,
            channel_count,
            downsamplings,
            channel_indices,
        )

    channel_metadata = [
        {
            'name': channel_names[i],
            'seriesRange': channel_ranges[i],
            'index': selected_channel_indices[i]
        }
        for i in range(len(channel_ranges))
    ]

    write_index_json(
        chunk_dir=chunk_dir,
        time_interval=time_interval,
        series_range=signal_range,
        channel_metadata=channel_metadata,
        chunk_size=chunk_size,
        downsamplings=list(range(len(shapes))),
        valid_samples_in_last_chunk=valid_samples_in_last_chunk,
        shapes=shapes,
    )

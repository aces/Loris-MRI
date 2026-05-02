from io import BytesIO
from typing import cast

import matplotlib.pyplot as plt
import mne
import numpy as np
import numpy.typing as npt
from fastapi import HTTPException
from fastapi.responses import StreamingResponse
from lib.config import get_data_dir_path_config
from lib.db.models.physio_file import DbPhysioFile
from lib.env import Env
from mne.io import BaseRaw


def read_physio_file_mne_raw(env: Env, physio_file: DbPhysioFile) -> BaseRaw | None:
    """
    Get the MNE raw object of a LORIS electrophysiology file if that file type is supported.
    """

    data_dir_path = get_data_dir_path_config(env)

    match physio_file.type:
        case 'ctf':
            raw = mne.io.read_raw_ctf(data_dir_path / physio_file.path)  # type: ignore
            # raw.pick('meg', exclude='ref_meg')
            raw.pick_types(meg=True, ref_meg=False)
            return raw
        case 'edf':
            raw = mne.io.read_raw_edf(data_dir_path / physio_file.path)  # type: ignore
            raw.set_montage('biosemi128')  # type: ignore
            raw.pick('eeg')  # type: ignore
            return raw
        case 'set':
            raw = mne.io.read_raw_eeglab(data_dir_path / physio_file.path)  # type: ignore
            raw.pick('eeg')  # type: ignore
            return raw
        case _:
            return None


def get_topographic_map(
    env: Env,
    physio_file: DbPhysioFile,
    t_min: float | None,
    t_max: float | None,
    l_freq: float | None,
    h_freq: float | None,
) -> StreamingResponse:
    """
    Get the topographic map of a LORIS electrophysiology file.
    """

    raw = read_physio_file_mne_raw(env, physio_file)
    if raw is None:
        raise HTTPException(status_code=500, detail="Electrophysiology file type not supported.")

    # Crop the MNE raw according to the time window.
    raw.crop(tmin=t_min if t_min is not None else 0.0, tmax=t_max)  # type: ignore

    # Apply frequency filters if specified.
    if l_freq is not None or h_freq is not None:
        # Load the signal data for filtering.
        raw.load_data()  # type: ignore

        # Filter the signal data with the provided low and high pass.
        raw.filter(  # type: ignore
            l_freq=l_freq,
            h_freq=h_freq,
            picks='all',
            method='fir',
            phase='zero',
            verbose=False,
        )

    # Get the mean signal values of the channels over time.
    data_raw = cast(npt.NDArray[np.float64], raw.get_data().mean(axis=1))  # type: ignore

    # Plot the topographic map.
    figure, axes = plt.subplots()  # type: ignore
    _, _ = mne.viz.plot_topomap(  # type: ignore
        data_raw,
        raw.info,  # type: ignore
        axes=axes,
        show=False,
        contours=0,
    )

    # Write the figure to a buffer for streaming.
    buffer = BytesIO()
    figure.savefig(buffer, format='png', dpi=150, bbox_inches='tight')  # type: ignore
    plt.close(figure)

    # Reset the stream position to the start of the buffer.
    buffer.seek(0)

    return StreamingResponse(buffer, media_type='image/png')

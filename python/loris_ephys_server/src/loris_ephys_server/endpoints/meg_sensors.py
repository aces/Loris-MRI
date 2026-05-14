from typing import Any, cast

import mne.io
import numpy as np
import numpy.typing as npt
from fastapi import HTTPException
from lib.config import get_data_dir_path_config
from lib.db.models.physio_file import DbPhysioFile
from lib.env import Env
from mne.io.constants import FIFF
from pydantic import BaseModel

from loris_ephys_server.jsonize import jsonize


def get_ephys_unit_symbol(unit_code: int) -> str | None:
    match unit_code:
        case FIFF.FIFF_UNIT_V:  # type: ignore
            # Used by EEG electrodes.
            return 'V'
        case FIFF.FIFF_UNIT_SEC:  # type: ignore
            # Used by MEG system clock.
            return 's'
        case FIFF.FIFF_UNIT_T:  # type: ignore
            # Used by MEG magnetometers.
            return 'T'
        case FIFF.FIFF_UNIT_T_M:  # type: ignore
            # Used by MEG gradiometers.
            return 'T/m'
        case _:
            return None


class MegSensorPoint(BaseModel):
    x: float
    y: float
    z: float
    unit: str | None
    type: Any


class MegSensorsResponse(BaseModel):
    sensors: dict[str, MegSensorPoint]


def get_meg_sensors(env: Env, physio_file: DbPhysioFile) -> MegSensorsResponse:
    """
    Get the head MEG sensors of a LORIS MEG file.
    """

    if physio_file.type != 'ctf':
        raise HTTPException(status_code=404, detail="Electrophysiology file is not an MEG file.")

    data_dir_path = get_data_dir_path_config(env)

    raw = mne.io.read_raw_ctf(data_dir_path / physio_file.path)  # type: ignore

    # Get the transformation from the device to the head coordinates system.
    dev_head_t = raw.info.get('dev_head_t')  # type: ignore
    if dev_head_t is None:
        raise HTTPException(status_code=500, detail="No device-to-head transformation found in the CTF file.")

    # The transformation matrix is a 4x4 array.
    transform = cast(npt.NDArray[np.float64], dev_head_t['trans'])

    sensors: dict[str, MegSensorPoint] = {}
    for channel in raw.info["chs"]:  # type: ignore
        channel_loc = cast(list[float], channel['loc'])

        # Sensor position in device coordinates (meters)
        device_pos = np.array([
            channel_loc[0],
            channel_loc[1],
            channel_loc[2],
            1.0  # Homogeneous coordinates
        ])

        # Transform to head coordinates
        head_pos = transform @ device_pos

        sensors[channel['ch_name']] = MegSensorPoint(
            x = float(head_pos[0]),
            y = float(head_pos[1]),
            z = float(head_pos[2]),
            unit = get_ephys_unit_symbol(channel['unit']),
            type = jsonize(channel),
        )

    return MegSensorsResponse(sensors=sensors)

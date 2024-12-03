from typing import Any

import mne.io
from fastapi import HTTPException
from lib.config import get_data_dir_path_config
from lib.db.queries.physio_file import try_get_physio_file_with_id
from lib.env import Env

from loris_meg.jsonize import jsonize


def get_meg_channels(env: Env, physio_file_id: int):
    # Fetch the physio file
    physio_file = try_get_physio_file_with_id(env.db, physio_file_id)
    if physio_file is None:
        raise HTTPException(status_code=404, detail="Physiological file not found.")

    data_dir_path = get_data_dir_path_config(env)

    match physio_file.type:
        case 'ctf':
            raw = mne.io.read_raw_ctf(data_dir_path / physio_file.path)  # type: ignore
        case 'edf':
            raw = mne.io.read_raw_edf(data_dir_path / physio_file.path)  # type: ignore
        case 'set':
            raw = mne.io.read_raw_eeglab(data_dir_path / physio_file.path)  # type: ignore
        case str():
            raise HTTPException(status_code=404, detail=f"Unknown file type '{physio_file.type}'")
        case None:
            raise HTTPException(status_code=404, detail="No file type")

    channels: list[Any] = []
    for channel in raw.info["chs"]:  # type: ignore
        channels.append(jsonize(channel))

    return {'channels': channels}

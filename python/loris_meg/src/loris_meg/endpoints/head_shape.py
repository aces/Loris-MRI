from fastapi import HTTPException
from lib.config import get_data_dir_path_config
from lib.db.queries.physio_file import try_get_physio_file_with_id
from lib.env import Env
from loris_bids_reader.meg.head_shape import MegCtfHeadShapeFile


def get_meg_head_shape(env: Env, physio_file_id: int):
    physio_file = try_get_physio_file_with_id(env.db, physio_file_id)
    if physio_file is None or physio_file.head_shape_file is None:
        raise HTTPException(status_code=404, detail="Physiological file not found.")

    data_dir_path = get_data_dir_path_config(env)

    head_shape_path = data_dir_path / physio_file.head_shape_file.path
    head_shape_file = MegCtfHeadShapeFile(head_shape_path)

    points: dict[str, dict[str, float]] = {}
    for name, point in head_shape_file.points.items():
        points[name] = {
            'x': float(point.x),
            'y': float(point.y),
            'z': float(point.z),
        }

    return {'points': points}

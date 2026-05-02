from fastapi import HTTPException
from lib.config import get_data_dir_path_config
from lib.db.models.physio_file import DbPhysioFile
from lib.env import Env
from loris_bids_reader.meg.head_shape import MegCtfHeadShapeFile
from pydantic import BaseModel


class MegHeadShapePoint(BaseModel):
    x: float
    y: float
    z: float


class MegHeadShapeResponse(BaseModel):
    points: dict[str, MegHeadShapePoint]


def get_meg_head_shape(env: Env, physio_file: DbPhysioFile):
    """
    Get the head shape points of a LORIS MEG file.
    """

    if physio_file.type != 'ctf':
        raise HTTPException(status_code=404, detail="Electrophysiology file is not an MEG file.")

    if physio_file.head_shape_file is None:
        raise HTTPException(status_code=404, detail="Headshape file not found.")

    data_dir_path = get_data_dir_path_config(env)

    head_shape_path = data_dir_path / physio_file.head_shape_file.path
    head_shape_file = MegCtfHeadShapeFile(head_shape_path)

    points: dict[str, MegHeadShapePoint] = {}
    for name, point in head_shape_file.points.items():
        points[name] = MegHeadShapePoint(
            x = float(point.x) / 100,
            y = float(point.y) / 100,
            z = float(point.z) / 100,
        )

    return MegHeadShapeResponse(points=points)

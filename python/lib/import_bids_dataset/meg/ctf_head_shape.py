from pathlib import Path

from loris_bids_reader.meg.head_shape import MegCtfHeadShapeFile
from loris_utils.crypto import compute_file_blake2b_hash

from lib.db.models.meg_ctf_head_shape_file import DbMegCtfHeadShapeFile
from lib.db.models.meg_ctf_head_shape_point import DbMegCtfHeadShapePoint
from lib.env import Env


def insert_head_shape_file(
    env: Env,
    head_shape_file: MegCtfHeadShapeFile,
    loris_head_shape_file_path: Path,
) -> DbMegCtfHeadShapeFile:
    """
    Insert a MEG CTF head shape file into the LORIS database.
    """

    blake2b_hash = compute_file_blake2b_hash(head_shape_file.path)

    db_head_shape_file = DbMegCtfHeadShapeFile(
        path         = loris_head_shape_file_path,
        blake2b_hash = blake2b_hash,
    )

    env.db.add(db_head_shape_file)
    env.db.flush()

    for name, point in head_shape_file.points.items():
        env.db.add(DbMegCtfHeadShapePoint(
            file_id = db_head_shape_file.id,
            name    = name,
            x       = point.x,
            y       = point.y,
            z       = point.z,
        ))

    env.db.flush()
    return db_head_shape_file

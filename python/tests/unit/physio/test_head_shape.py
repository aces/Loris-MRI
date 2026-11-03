from decimal import Decimal
from pathlib import Path

from loris_bids_utils.meg.ctf.head_shape import MegCtfHeadShapeFile

from lib.db.models.bids_file import DbBidsFile
from lib.db.queries.meg_ctf_head_shape import try_get_meg_ctf_head_shape_file_with_path
from lib.env import Env
from lib.physio.ctf.head_shape import insert_meg_ctf_head_shape_file


def test_insert_preserves_repeated_head_shape_labels(env: Env, tmp_path: Path):
    path = tmp_path / 'headshape.pos'
    path.write_text('0\nNasion\t1.0\t2.0\t3.0\nNasion\t4.0\t5.0\t6.0\n')
    bids_info = DbBidsFile(
        dataset_id = 1,
        path = path,
        blake2b_hash = 'test',
        derivative = False,
    )
    env.db.add(bids_info)
    env.db.flush()

    insert_meg_ctf_head_shape_file(env, MegCtfHeadShapeFile.read(path), path, bids_info)
    env.db.expire_all()
    stored = try_get_meg_ctf_head_shape_file_with_path(env.db, path)

    assert stored is not None
    assert sorted((point.name, point.x, point.y, point.z) for point in stored.points) == [
        ('Nasion', Decimal(1), Decimal(2), Decimal(3)),
        ('Nasion', Decimal(4), Decimal(5), Decimal(6)),
    ]

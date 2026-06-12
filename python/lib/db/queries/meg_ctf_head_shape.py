from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.meg_ctf_head_shape_file import DbMegCtfHeadShapeFile


def try_get_meg_ctf_head_shape_file_with_path(db: Database, path: Path) -> DbMegCtfHeadShapeFile | None:
    return db.execute(select(DbMegCtfHeadShapeFile)
        .where(DbMegCtfHeadShapeFile.path == path)
    ).scalar_one_or_none()

from pathlib import Path

from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.meg_ctf_head_shape_point as db_meg_ctf_head_shape_point
from lib.db.base import Base
from lib.db.decorators.string_path import StringPath


class DbMegCtfHeadShapeFile(Base):
    """
    A MEG CTF `headshape.pos` file. This file contains 3D points positioned on the subject head and
    is shared by all the CTF files of an MEG acquisition.
    """

    __tablename__ = 'meg_ctf_head_shape_file'

    id: Mapped[int]  = mapped_column('ID', primary_key=True)
    """
    ID of the head shape file.
    """

    path: Mapped[Path] = mapped_column('Path', StringPath)
    """
    Path of the head shape file relative to the LORIS data directory.
    """

    blake2b_hash: Mapped[str] = mapped_column('Blake2bHash')
    """
    Blake2B hash of the head shape file, which may be used to check that the on-disk file data
    matches the file registered in the LORIS database.
    """

    points: Mapped[list['db_meg_ctf_head_shape_point.DbMegCtfHeadShapePoint']] = relationship('DbMegCtfHeadShapePoint', back_populates='file')
    """
    3D points present in the head shape file.
    """

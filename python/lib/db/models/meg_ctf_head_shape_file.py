from datetime import datetime
from pathlib import Path

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.bids_file as db_bids_file
import lib.db.models.meg_ctf_head_shape_point as db_meg_ctf_head_shape_point
from lib.db.base import Base
from lib.db.decorators.string_path import StringPath


class DbMegCtfHeadShapeFile(Base):
    """
    A MEG CTF `headshape.pos` file. This file contains 3D points positioned on the subject head and
    is shared by all the CTF files of an MEG acquisition.
    """

    __tablename__ = 'meg_ctf_head_shape_file'

    id: Mapped[int] = mapped_column('ID', primary_key=True)
    """
    ID of the head shape file.
    """

    bids_info_id: Mapped[int | None] = mapped_column('BidsInfoID', ForeignKey('bids_file.ID', ondelete='SET NULL'))
    """
    The ID of the BIDS information of this head shape file, if any.
    """

    path: Mapped[Path] = mapped_column('Path', StringPath)
    """
    Path of the head shape file relative to the LORIS data directory.
    """

    insert_time: Mapped[datetime] = mapped_column('InsertTime', default=datetime.now)
    """
    The time at which this head shape file was created in LORIS.
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

    bids_info: Mapped['db_bids_file.DbBidsFile | None'] = relationship('DbBidsFile')
    """
    The BIDS information of this head shape file, if any.
    """

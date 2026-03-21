from decimal import Decimal

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.meg_ctf_head_shape_file as db_meg_ctf_head_shape_file
from lib.db.base import Base


# TODO: It might be possible that headshape files contain points in other units than centimeters,
# in which case the database should be extended to handle it.
class DbMegCtfHeadShapePoint(Base):
    """
    A 3D point present in a MEG CTF `headshape.pos` file.
    """

    __tablename__ = 'meg_ctf_head_shape_point'

    id: Mapped[int] = mapped_column('ID', primary_key=True)
    """
    ID of the head shape point.
    """

    file_id: Mapped[int] = mapped_column('FileID', ForeignKey('meg_ctf_head_shape_file.ID'))
    """
    ID of the head shape file to which this point belongs.
    """

    name: Mapped[str] = mapped_column('Name')
    """
    Name of the point, which may either be an integer or an anatomical landmark label.
    """

    x: Mapped[Decimal] = mapped_column('X')
    """
    X coordinate of the point in the head shape file, in centimeters.
    """

    y: Mapped[Decimal] = mapped_column('Y')
    """
    Y coordinate of the point in the head shape file, in centimeters.
    """

    z: Mapped[Decimal] = mapped_column('Z')
    """
    Z coordinate of the point in the head shape file, in centimeters.
    """

    file: Mapped['db_meg_ctf_head_shape_file.DbMegCtfHeadShapeFile'] = relationship('DbMegCtfHeadShapeFile', back_populates='points')
    """
    The head shape file to which this point belongs.
    """

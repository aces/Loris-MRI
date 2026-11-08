from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.bids_file as db_bids_file
from lib.db.base import Base


class DbBidsFileEntity(Base):
    """
    A BIDS key-value entity present in a BIDS file name.
    """

    __tablename__ = 'bids_file_entity'

    id: Mapped[int] = mapped_column('ID', primary_key=True, autoincrement=True)
    """
    The ID of this BIDS file entity.
    """

    file_id: Mapped[int] = mapped_column('FileID', ForeignKey('bids_file.ID', ondelete='CASCADE'))
    """
    The ID of the BIDS file to which this entity belongs.
    """

    key: Mapped[str] = mapped_column('Key')
    """
    The entity key, such as `sub`, `task`, or `run`.
    """

    value: Mapped[str] = mapped_column('Value')
    """
    The entity value.
    """

    file: Mapped['db_bids_file.DbBidsFile'] = relationship('DbBidsFile', back_populates='entities')
    """
    The BIDS file to which this entity belongs.
    """

from datetime import datetime
from pathlib import Path

from sqlalchemy import ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.bids_dataset as db_bids_dataset
from lib.db.base import Base
from lib.db.decorators.int_bool import IntBool
from lib.db.decorators.string_path import StringPath


class DbBidsFile(Base):
    """
    A file within a LORIS BIDS dataset.
    """

    __tablename__ = 'bids_file'
    __table_args__ = (
        UniqueConstraint('DatasetID', 'Path', name='bids_file_dataset_id_path_unique'),
    )

    id: Mapped[int] = mapped_column('ID', primary_key=True, autoincrement=True)
    """
    The ID of this BIDS file.
    """

    dataset_id: Mapped[int] = mapped_column('DatasetID', ForeignKey('bids_dataset.ID', ondelete='CASCADE'))
    """
    The ID of the BIDS dataset to which this file belongs.
    """

    path: Mapped[Path] = mapped_column('Path', StringPath)
    """
    The path of this file relative to its LORIS BIDS dataset.
    """

    source_path: Mapped[Path | None] = mapped_column('SourcePath', StringPath)
    """
    The source path of this file relative to the BIDS dataset from which it was imported.
    """

    insert_time: Mapped[datetime] = mapped_column('InsertTime', default=datetime.now)
    """
    The time at which this BIDS dataset was created in LORIS.
    """

    blake2b_hash: Mapped[str] = mapped_column('Blake2bHash')
    """
    The BLAKE2b hash of this file.
    """

    derivative: Mapped[bool] = mapped_column('Derivative', IntBool)
    """
    Whether this file is a BIDS derivative.
    """

    dataset: Mapped['db_bids_dataset.DbBidsDataset'] = relationship('DbBidsDataset')
    """
    The BIDS dataset to which this file belongs.
    """

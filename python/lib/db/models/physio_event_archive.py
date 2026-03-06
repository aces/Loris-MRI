from pathlib import Path

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_file as db_physio_file
from lib.db.base import Base
from lib.db.decorators.string_path import StringPath


class DbPhysioEventArchive(Base):
    __tablename__ = 'physiological_event_archive'

    id             : Mapped[int]  = mapped_column('EventArchiveID', primary_key=True)
    physio_file_id : Mapped[int]  = mapped_column('PhysiologicalFileID', ForeignKey('physiological_file.PhysiologicalFileID'))
    blake2b_hash   : Mapped[str]  = mapped_column('Blake2bHash')
    file_path      : Mapped[Path] = mapped_column('FilePath', StringPath)

    physio_file: Mapped['db_physio_file.DbPhysioFile'] = relationship('DbPhysioFile')

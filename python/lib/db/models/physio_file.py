from datetime import datetime

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_file_parameter as db_phyiso_file_parameter
import lib.db.models.physio_modality as db_physio_modality
import lib.db.models.physio_output_type as db_physio_output_type
from lib.db.base import Base


class DbPhysioFile(Base):
    __tablename__ = 'physiological_file'

    id               : Mapped[int]             = mapped_column('PhysiologicalFileID', primary_key=True)
    modality_id      : Mapped[int | None]      = mapped_column('PhysiologicalModalityID', ForeignKey('physiological_modality.PhysiologicalModalityID'))
    output_type_id   : Mapped[int ]            = mapped_column('PhysiologicalOutputTypeID', ForeignKey('physiological_output_type.PhysiologicalOutputTypeID'))
    session_id       : Mapped[int ]            = mapped_column('SessionID')
    insert_time      : Mapped[datetime]        = mapped_column('InsertTime')
    file_type        : Mapped[str | None]      = mapped_column('FileType')
    acquisition_time : Mapped[datetime | None] = mapped_column('AcquisitionTime')
    inserted_by_user : Mapped[str]             = mapped_column('InsertedByUser')
    path             : Mapped[str]             = mapped_column('FilePath')
    index            : Mapped[int | None]      = mapped_column('Index')
    parent_id        : Mapped[int | None]      = mapped_column('ParentID')

    output_type : Mapped['db_physio_output_type.DbPhysioOutputType']       = relationship('DbPhysioOutputType')
    modality    : Mapped['db_physio_modality.DbPhysioModality | None']     = relationship('DbPhysioModality')
    parameters  : Mapped['db_phyiso_file_parameter.DbPhysioFileParameter'] = relationship('DbPhysioFileParameter', back_populates='file')

from datetime import datetime
from pathlib import Path

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.dicom_archive as db_dicom_archive
from lib.db.base import Base
from lib.db.decorators.string_path import StringPath


class DbMriCandidateError(Base):
    __tablename__ = 'MRICandidateErrors'

    id                       : Mapped[int]          = mapped_column('ID', primary_key=True)
    time_run                 : Mapped[datetime]     = mapped_column('TimeRun', default=datetime.now)
    series_uid               : Mapped[str | None]   = mapped_column('SeriesUID')
    dicom_archive_id         : Mapped[int | None]   = mapped_column('TarchiveID', ForeignKey('tarchive.TarchiveID'))
    file_path                : Mapped[Path | None]  = mapped_column('MincFile', StringPath)
    patient_name             : Mapped[str | None]   = mapped_column('PatientName')
    reason                   : Mapped[str | None]   = mapped_column('Reason')
    echo_time                : Mapped[float | None] = mapped_column('EchoTime')
    phase_encoding_direction : Mapped[str | None]   = mapped_column('PhaseEncodingDirection')
    echo_number              : Mapped[str | None]   = mapped_column('EchoNumber')

    archive: Mapped['db_dicom_archive.DbDicomArchive | None'] = relationship('DbDicomArchive')

from typing import List, Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.model.dicom_archive as db_dicom_archive
import lib.db.model.dicom_archive_file as db_dicom_archive_file
from lib.db.base import Base


class DbDicomArchiveSeries(Base):
    __tablename__ = 'tarchive_series'

    id                 : Mapped[int]             = mapped_column('TarchiveSeriesID', primary_key=True)
    archive_id         : Mapped[int]             = mapped_column('TarchiveID', ForeignKey('tarchive.TarchiveID'))
    series_number      : Mapped[int]             = mapped_column('SeriesNumber')
    series_description : Mapped[Optional[str]]   = mapped_column('SeriesDescription')
    sequence_name      : Mapped[Optional[str]]   = mapped_column('SequenceName')
    echo_time          : Mapped[Optional[float]] = mapped_column('EchoTime')
    repetition_time    : Mapped[Optional[float]] = mapped_column('RepetitionTime')
    inversion_time     : Mapped[Optional[float]] = mapped_column('InversionTime')
    slice_thickness    : Mapped[Optional[float]] = mapped_column('SliceThickness')
    phase_encoding     : Mapped[Optional[str]]   = mapped_column('PhaseEncoding')
    number_of_files    : Mapped[int]             = mapped_column('NumberOfFiles')
    series_uid         : Mapped[Optional[str]]   = mapped_column('SeriesUID')
    modality           : Mapped[Optional[str]]   = mapped_column('Modality')

    archive            : Mapped['db_dicom_archive.DbDicomArchive'] \
        = relationship('DbDicomArchive', back_populates='series')
    files              : Mapped[List['db_dicom_archive_file.DbDicomArchiveFile']] \
        = relationship('DbDicomArchiveFile', back_populates='series')

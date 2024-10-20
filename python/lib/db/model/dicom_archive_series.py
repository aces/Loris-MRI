from typing import List, Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.model.dicom_archive as db_dicom_archive
import lib.db.model.dicom_archive_file as db_dicom_archive_file
from lib.db.base import Base


class DbDicomArchiveSeries(Base):
    __tablename__ = 'tarchive_series'

    id                 : Mapped[int]             = mapped_column('TarchiveSeriesID',
        primary_key=True, autoincrement=True, init=False)
    archive_id         : Mapped[int]             = mapped_column('TarchiveID', ForeignKey('tarchive.TarchiveID'))
    series_number      : Mapped[int]             = mapped_column('SeriesNumber',      default=0)
    series_description : Mapped[Optional[str]]   = mapped_column('SeriesDescription', default=None)
    sequence_name      : Mapped[Optional[str]]   = mapped_column('SequenceName',      default=None)
    echo_time          : Mapped[Optional[float]] = mapped_column('EchoTime',          default=None)
    repetition_time    : Mapped[Optional[float]] = mapped_column('RepetitionTime',    default=None)
    inversion_time     : Mapped[Optional[float]] = mapped_column('InversionTime',     default=None)
    slice_thickness    : Mapped[Optional[float]] = mapped_column('SliceThickness',    default=None)
    phase_encoding     : Mapped[Optional[str]]   = mapped_column('PhaseEncoding',     default=None)
    number_of_files    : Mapped[int]             = mapped_column('NumberOfFiles',     default=0)
    series_uid         : Mapped[Optional[str]]   = mapped_column('SeriesUID',         default=None)
    modality           : Mapped[Optional[str]]   = mapped_column('Modality',          default=None)

    archive            : Mapped['db_dicom_archive.DbDicomArchive'] \
        = relationship('DbDicomArchive', back_populates='series', init=False)

    files              : Mapped[List['db_dicom_archive_file.DbDicomArchiveFile']] \
        = relationship('DbDicomArchiveFile', back_populates='series', init=False)

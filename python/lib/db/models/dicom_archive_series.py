from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.dicom_archive as db_dicom_archive
import lib.db.models.dicom_archive_file as db_dicom_archive_file
from lib.db.base import Base


class DbDicomArchiveSeries(Base):
    __tablename__ = 'tarchive_series'

    id                 : Mapped[int]          = mapped_column('TarchiveSeriesID', primary_key=True)
    archive_id         : Mapped[int]          = mapped_column('TarchiveID', ForeignKey('tarchive.TarchiveID'))
    series_number      : Mapped[int]          = mapped_column('SeriesNumber')
    series_description : Mapped[str | None]   = mapped_column('SeriesDescription')
    sequence_name      : Mapped[str | None]   = mapped_column('SequenceName')
    echo_time          : Mapped[float | None] = mapped_column('EchoTime')
    repetition_time    : Mapped[float | None] = mapped_column('RepetitionTime')
    inversion_time     : Mapped[float | None] = mapped_column('InversionTime')
    slice_thickness    : Mapped[float | None] = mapped_column('SliceThickness')
    phase_encoding     : Mapped[str | None]   = mapped_column('PhaseEncoding')
    number_of_files    : Mapped[int]          = mapped_column('NumberOfFiles')
    series_uid         : Mapped[str | None]   = mapped_column('SeriesUID')
    modality           : Mapped[str | None]   = mapped_column('Modality')

    archive            : Mapped['db_dicom_archive.DbDicomArchive'] \
        = relationship('DbDicomArchive', back_populates='series')
    files              : Mapped[list['db_dicom_archive_file.DbDicomArchiveFile']] \
        = relationship('DbDicomArchiveFile', back_populates='series')

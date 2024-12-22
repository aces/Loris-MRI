from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.dicom_archive as db_dicom_archive
import lib.db.models.dicom_archive_series as db_dicom_archive_series
from lib.db.base import Base


class DbDicomArchiveFile(Base):
    __tablename__ = 'tarchive_files'

    id                 : Mapped[int]           = mapped_column('TarchiveFileID', primary_key=True)
    archive_id         : Mapped[int]           = mapped_column('TarchiveID', ForeignKey('tarchive.TarchiveID'))
    series_id          : Mapped[Optional[int]] \
        = mapped_column('TarchiveSeriesID', ForeignKey('tarchive_series.TarchiveSeriesID'))
    series_number      : Mapped[Optional[int]] = mapped_column('SeriesNumber')
    series_description : Mapped[Optional[str]] = mapped_column('SeriesDescription')
    file_number        : Mapped[Optional[int]] = mapped_column('FileNumber')
    echo_number        : Mapped[Optional[int]] = mapped_column('EchoNumber')
    md5_sum            : Mapped[str]           = mapped_column('Md5Sum')
    file_name          : Mapped[str]           = mapped_column('FileName')

    archive : Mapped['db_dicom_archive.DbDicomArchive'] \
        = relationship('DbDicomArchive', back_populates='files')
    series  : Mapped[Optional['db_dicom_archive_series.DbDicomArchiveSeries']] \
        = relationship('DbDicomArchiveSeries', back_populates='files')

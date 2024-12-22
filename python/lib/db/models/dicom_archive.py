from datetime import date, datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.dicom_archive_file as db_dicom_archive_file
import lib.db.models.dicom_archive_series as db_dicom_archive_series
import lib.db.models.mri_upload as db_mri_upload
import lib.db.models.session as db_session
from lib.db.base import Base


class DbDicomArchive(Base):
    __tablename__ = 'tarchive'

    id                       : Mapped[int]                = mapped_column('TarchiveID', primary_key=True)
    study_uid                : Mapped[str]                = mapped_column('DicomArchiveID')
    patient_id               : Mapped[str]                = mapped_column('PatientID')
    patient_name             : Mapped[str]                = mapped_column('PatientName')
    patient_birthdate        : Mapped[Optional[date]]     = mapped_column('PatientDoB')
    patient_sex              : Mapped[Optional[str]]      = mapped_column('PatientSex')
    neuro_db_center_name     : Mapped[Optional[str]]      = mapped_column('neurodbCenterName')
    center_name              : Mapped[str]                = mapped_column('CenterName')
    last_update              : Mapped[Optional[datetime]] = mapped_column('LastUpdate')
    date_acquired            : Mapped[Optional[date]]     = mapped_column('DateAcquired')
    date_first_archived      : Mapped[Optional[datetime]] = mapped_column('DateFirstArchived')
    date_last_archived       : Mapped[Optional[datetime]] = mapped_column('DateLastArchived')
    acquisition_count        : Mapped[int]                = mapped_column('AcquisitionCount')
    dicom_file_count         : Mapped[int]                = mapped_column('DicomFileCount')
    non_dicom_file_count     : Mapped[int]                = mapped_column('NonDicomFileCount')
    md5_sum_dicom_only       : Mapped[Optional[str]]      = mapped_column('md5sumDicomOnly')
    md5_sum_archive          : Mapped[Optional[str]]      = mapped_column('md5sumArchive')
    creating_user            : Mapped[str]                = mapped_column('CreatingUser')
    sum_type_version         : Mapped[int]                = mapped_column('sumTypeVersion')
    tar_type_version         : Mapped[Optional[int]]      = mapped_column('tarTypeVersion')
    source_location          : Mapped[str]                = mapped_column('SourceLocation')
    archive_location         : Mapped[Optional[str]]      = mapped_column('ArchiveLocation')
    scanner_manufacturer     : Mapped[str]                = mapped_column('ScannerManufacturer')
    scanner_model            : Mapped[str]                = mapped_column('ScannerModel')
    scanner_serial_number    : Mapped[str]                = mapped_column('ScannerSerialNumber')
    scanner_software_version : Mapped[str]                = mapped_column('ScannerSoftwareVersion')
    session_id               : Mapped[Optional[int]]      = mapped_column('SessionID', ForeignKey('session.ID'))
    upload_attempt           : Mapped[int]                = mapped_column('uploadAttempt')
    create_info              : Mapped[Optional[str]]      = mapped_column('CreateInfo')
    acquisition_metadata     : Mapped[str]                = mapped_column('AcquisitionMetadata')
    date_sent                : Mapped[Optional[datetime]] = mapped_column('DateSent')
    pending_transfer         : Mapped[bool]               = mapped_column('PendingTransfer')

    series  : Mapped[list['db_dicom_archive_series.DbDicomArchiveSeries']] \
        = relationship('DbDicomArchiveSeries', back_populates='archive')
    files   : Mapped[list['db_dicom_archive_file.DbDicomArchiveFile']] \
        = relationship('DbDicomArchiveFile', back_populates='archive')
    upload  : Mapped[Optional['db_mri_upload.DbMriUpload']] \
        = relationship('DbMriUpload', back_populates='dicom_archive')
    session : Mapped[Optional['db_session.DbSession']] \
        = relationship('DbSession')

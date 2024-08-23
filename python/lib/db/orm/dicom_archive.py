from datetime import date, datetime
from typing import List, Optional
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from lib.db.base import Base
import lib.db.orm.dicom_archive_file as dicom_archive_file
import lib.db.orm.dicom_archive_series as dicom_archive_series
import lib.db.orm.mri_upload as mri_upload


class DbDicomArchive(Base):
    __tablename__ = 'tarchive'

    id                       : Mapped[int]                = mapped_column('TarchiveID', primary_key=True)
    series                   : Mapped[List['dicom_archive_series.DbDicomArchiveSeries']] \
        = relationship('DbDicomArchiveSeries', back_populates='archive')
    files                    : Mapped[List['dicom_archive_file.DbDicomArchiveFile']] \
        = relationship('DbDicomArchiveFile', back_populates='archive')
    upload                   : Mapped[Optional['mri_upload.DbMriUpload']] \
        = relationship('DbMriUpload', back_populates='dicom_archive')
    study_uid                : Mapped[str]                = mapped_column('DicomArchiveID', type_ = String())
    patient_id               : Mapped[str]                = mapped_column('PatientID')
    patient_name             : Mapped[str]                = mapped_column('PatientName')
    patient_birthdate        : Mapped[Optional[date]]     = mapped_column('PatientDoB')
    patient_sex              : Mapped[Optional[str]]      = mapped_column('PatientSex')
    neuro_db_center_name     : Mapped[Optional[str]]      = mapped_column('neurodbCenterName')
    center_name              : Mapped[str]                = mapped_column('CenterName')
    last_update              : Mapped[Optional[date]]     = mapped_column('LastUpdate')
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
    session_id               : Mapped[Optional[int]]      = mapped_column('SessionID')
    upload_attempt           : Mapped[int]                = mapped_column('uploadAttempt')
    create_info              : Mapped[Optional[str]]      = mapped_column('CreateInfo')
    acquisition_metadata     : Mapped[str]                = mapped_column('AcquisitionMetadata')
    date_sent                : Mapped[Optional[datetime]] = mapped_column('DateSent')
    pending_transfer         : Mapped[int]                = mapped_column('PendingTransfer')

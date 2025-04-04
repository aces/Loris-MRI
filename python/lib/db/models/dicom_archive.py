from datetime import date, datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.dicom_archive_file as db_dicom_archive_file
import lib.db.models.dicom_archive_series as db_dicom_archive_series
import lib.db.models.mri_protocol_violated_scans as db_mri_protocol_violated_scans
import lib.db.models.mri_upload as db_mri_upload
import lib.db.models.mri_violations_log as db_mri_violations_log
import lib.db.models.session as db_session
from lib.db.base import Base


class DbDicomArchive(Base):
    __tablename__ = 'tarchive'

    id                       : Mapped[int]             = mapped_column('TarchiveID', primary_key=True)
    study_uid                : Mapped[str]             = mapped_column('DicomArchiveID')
    patient_id               : Mapped[str]             = mapped_column('PatientID')
    patient_name             : Mapped[str]             = mapped_column('PatientName')
    patient_birthdate        : Mapped[date | None]     = mapped_column('PatientDoB')
    patient_sex              : Mapped[str | None]      = mapped_column('PatientSex')
    neuro_db_center_name     : Mapped[str | None]      = mapped_column('neurodbCenterName')
    center_name              : Mapped[str]             = mapped_column('CenterName')
    last_update              : Mapped[datetime | None] = mapped_column('LastUpdate')
    date_acquired            : Mapped[date | None]     = mapped_column('DateAcquired')
    date_first_archived      : Mapped[datetime | None] = mapped_column('DateFirstArchived')
    date_last_archived       : Mapped[datetime | None] = mapped_column('DateLastArchived')
    acquisition_count        : Mapped[int]             = mapped_column('AcquisitionCount')
    dicom_file_count         : Mapped[int]             = mapped_column('DicomFileCount')
    non_dicom_file_count     : Mapped[int]             = mapped_column('NonDicomFileCount')
    md5_sum_dicom_only       : Mapped[str | None]      = mapped_column('md5sumDicomOnly')
    md5_sum_archive          : Mapped[str | None]      = mapped_column('md5sumArchive')
    creating_user            : Mapped[str]             = mapped_column('CreatingUser')
    sum_type_version         : Mapped[int]             = mapped_column('sumTypeVersion')
    tar_type_version         : Mapped[int | None]      = mapped_column('tarTypeVersion')
    source_location          : Mapped[str]             = mapped_column('SourceLocation')
    archive_location         : Mapped[str | None]      = mapped_column('ArchiveLocation')
    scanner_manufacturer     : Mapped[str]             = mapped_column('ScannerManufacturer')
    scanner_model            : Mapped[str]             = mapped_column('ScannerModel')
    scanner_serial_number    : Mapped[str]             = mapped_column('ScannerSerialNumber')
    scanner_software_version : Mapped[str]             = mapped_column('ScannerSoftwareVersion')
    session_id               : Mapped[int | None]      = mapped_column('SessionID', ForeignKey('session.ID'))
    upload_attempt           : Mapped[int]             = mapped_column('uploadAttempt')
    create_info              : Mapped[str | None]      = mapped_column('CreateInfo')
    acquisition_metadata     : Mapped[str]             = mapped_column('AcquisitionMetadata')
    date_sent                : Mapped[datetime | None] = mapped_column('DateSent')
    pending_transfer         : Mapped[bool]            = mapped_column('PendingTransfer')

    series      : Mapped[list['db_dicom_archive_series.DbDicomArchiveSeries']] \
        = relationship('DbDicomArchiveSeries', back_populates='archive')
    files       : Mapped[list['db_dicom_archive_file.DbDicomArchiveFile']] \
        = relationship('DbDicomArchiveFile', back_populates='archive')
    mri_uploads : Mapped[list['db_mri_upload.DbMriUpload']] \
        = relationship('DbMriUpload', back_populates='dicom_archive')
    session     : Mapped[Optional['db_session.DbSession']] \
        = relationship('DbSession')
    violated_scans: Mapped[Optional['db_mri_protocol_violated_scans.DbMriProtocolViolatedScans']] \
        = relationship('DbMriProtocolViolatedScans', back_populates='archive')
    violations_log       : Mapped[Optional['db_mri_violations_log.DbMriViolationsLog']] \
        = relationship('DbMriViolationsLog', back_populates='archive')

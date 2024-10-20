from datetime import date, datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.model.dicom_archive_file as db_dicom_archive_file
import lib.db.model.dicom_archive_series as db_dicom_archive_series
import lib.db.model.mri_upload as db_mri_upload
import lib.db.model.session as db_session
from lib.db.base import Base


class DbDicomArchive(Base):
    __tablename__ = 'tarchive'

    create_info              : Mapped[Optional[str]]      = mapped_column('CreateInfo')
    acquisition_metadata     : Mapped[str]                = mapped_column('AcquisitionMetadata')
    id                       : Mapped[int]                = mapped_column('TarchiveID',
        primary_key=True, autoincrement=True, init=False)
    study_uid                : Mapped[str]                = mapped_column('DicomArchiveID',         default='')
    patient_id               : Mapped[str]                = mapped_column('PatientID',              default='')
    patient_name             : Mapped[str]                = mapped_column('PatientName',            default='')
    patient_birthdate        : Mapped[Optional[date]]     = mapped_column('PatientDoB',             default=None)
    patient_sex              : Mapped[Optional[str]]      = mapped_column('PatientSex',             default=None)
    neuro_db_center_name     : Mapped[Optional[str]]      = mapped_column('neurodbCenterName',      default=None)
    center_name              : Mapped[str]                = mapped_column('CenterName',             default='')
    last_update              : Mapped[Optional[datetime]] = mapped_column('LastUpdate',             default=None)
    date_acquired            : Mapped[Optional[date]]     = mapped_column('DateAcquired',           default=None)
    date_first_archived      : Mapped[Optional[datetime]] = mapped_column('DateFirstArchived',      default=None)
    date_last_archived       : Mapped[Optional[datetime]] = mapped_column('DateLastArchived',       default=None)
    acquisition_count        : Mapped[int]                = mapped_column('AcquisitionCount',       default=0)
    dicom_file_count         : Mapped[int]                = mapped_column('DicomFileCount',         default=0)
    non_dicom_file_count     : Mapped[int]                = mapped_column('NonDicomFileCount',      default=0)
    md5_sum_dicom_only       : Mapped[Optional[str]]      = mapped_column('md5sumDicomOnly',        default=None)
    md5_sum_archive          : Mapped[Optional[str]]      = mapped_column('md5sumArchive',          default=None)
    creating_user            : Mapped[str]                = mapped_column('CreatingUser',           default='')
    sum_type_version         : Mapped[int]                = mapped_column('sumTypeVersion',         default=0)
    tar_type_version         : Mapped[Optional[int]]      = mapped_column('tarTypeVersion',         default=None)
    source_location          : Mapped[str]                = mapped_column('SourceLocation',         default='')
    archive_location         : Mapped[Optional[str]]      = mapped_column('ArchiveLocation',        default=None)
    scanner_manufacturer     : Mapped[str]                = mapped_column('ScannerManufacturer',    default='')
    scanner_model            : Mapped[str]                = mapped_column('ScannerModel',           default='')
    scanner_serial_number    : Mapped[str]                = mapped_column('ScannerSerialNumber',    default='')
    scanner_software_version : Mapped[str]                = mapped_column('ScannerSoftwareVersion', default='')
    session_id               : Mapped[Optional[int]]      = mapped_column('SessionID',
        ForeignKey('session.ID'), default=None)
    upload_attempt           : Mapped[int]                = mapped_column('uploadAttempt',          default=0)
    date_sent                : Mapped[Optional[datetime]] = mapped_column('DateSent',               default=None)
    pending_transfer         : Mapped[bool]               = mapped_column('PendingTransfer',        default=False)

    series  : Mapped[list['db_dicom_archive_series.DbDicomArchiveSeries']] \
        = relationship('DbDicomArchiveSeries', back_populates='archive', init=False)
    files   : Mapped[list['db_dicom_archive_file.DbDicomArchiveFile']] \
        = relationship('DbDicomArchiveFile', back_populates='archive', init=False)
    upload  : Mapped[Optional['db_mri_upload.DbMriUpload']] \
        = relationship('DbMriUpload', back_populates='dicom_archive', init=False)
    session : Mapped[Optional['db_session.DbSession']] \
        = relationship('DbSession', init=False)

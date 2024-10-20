from datetime import datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.model.dicom_archive as db_dicom_archive
import lib.db.model.session as db_session
from lib.db.base import Base
from lib.db.decorator.y_n_bool import YNBool


class DbMriUpload(Base):
    __tablename__ = 'mri_upload'

    id                          : Mapped[int]                = mapped_column('UploadID',
        primary_key=True, autoincrement=True, init=False)
    uploaded_by                 : Mapped[str]                = mapped_column('UploadedBy',               default='')
    upload_date                 : Mapped[Optional[datetime]] = mapped_column('UploadDate',               default=None)
    upload_location             : Mapped[str]                = mapped_column('UploadLocation',           default='')
    decompressed_location       : Mapped[str]                = mapped_column('DecompressedLocation',     default='')
    insertion_complete          : Mapped[bool]               = mapped_column('InsertionComplete',        default=0)
    inserting                   : Mapped[Optional[bool]]     = mapped_column('Inserting',                default=None)
    patient_name                : Mapped[str]                = mapped_column('PatientName',              default='')
    number_of_minc_inserted     : Mapped[Optional[int]]      = mapped_column('number_of_mincInserted',   default=None)
    number_of_minc_created      : Mapped[Optional[int]]      = mapped_column('number_of_mincCreated',    default=None)
    dicom_archive_id            : Mapped[Optional[int]]      = mapped_column('TarchiveID',
        ForeignKey('tarchive.TarchiveID'), default=None)
    session_id                  : Mapped[Optional[int]]      = mapped_column('SessionID',
        ForeignKey('session.ID'), default=None)
    is_candidate_info_validated : Mapped[Optional[bool]]     = mapped_column('IsCandidateInfoValidated', default=0)
    is_dicom_archive_validated  : Mapped[bool]               = mapped_column('IsTarchiveValidated',      default=False)
    is_phantom                  : Mapped[bool]               = mapped_column('IsPhantom', YNBool,        default=False)

    dicom_archive               : Mapped[Optional['db_dicom_archive.DbDicomArchive']] \
        = relationship('DbDicomArchive', back_populates='upload', init=False)
    session                     : Mapped[Optional['db_session.DbSession']] \
        = relationship('DbSession', init=False)

from datetime import datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.dicom_archive as db_dicom_archive
import lib.db.models.session as db_session
from lib.db.base import Base
from lib.db.decorators.y_n_bool import YNBool


class DbMriUpload(Base):
    __tablename__ = 'mri_upload'

    id                          : Mapped[int]                = mapped_column('UploadID', primary_key=True)
    uploaded_by                 : Mapped[str]                = mapped_column('UploadedBy')
    upload_date                 : Mapped[Optional[datetime]] = mapped_column('UploadDate')
    upload_location             : Mapped[str]                = mapped_column('UploadLocation')
    decompressed_location       : Mapped[str]                = mapped_column('DecompressedLocation')
    insertion_complete          : Mapped[bool]               = mapped_column('InsertionComplete')
    inserting                   : Mapped[Optional[bool]]     = mapped_column('Inserting')
    patient_name                : Mapped[str]                = mapped_column('PatientName')
    number_of_minc_inserted     : Mapped[Optional[int]]      = mapped_column('number_of_mincInserted')
    number_of_minc_created      : Mapped[Optional[int]]      = mapped_column('number_of_mincCreated')
    dicom_archive_id            : Mapped[Optional[int]] \
        = mapped_column('TarchiveID', ForeignKey('tarchive.TarchiveID'))
    session_id                  : Mapped[Optional[int]]      = mapped_column('SessionID', ForeignKey('session.ID'))
    is_candidate_info_validated : Mapped[Optional[bool]]     = mapped_column('IsCandidateInfoValidated')
    is_dicom_archive_validated  : Mapped[bool]               = mapped_column('IsTarchiveValidated')
    is_phantom                  : Mapped[bool]               = mapped_column('IsPhantom', YNBool)

    dicom_archive               : Mapped[Optional['db_dicom_archive.DbDicomArchive']] \
        = relationship('DbDicomArchive', back_populates='upload')
    session                     : Mapped[Optional['db_session.DbSession']] \
        = relationship('DbSession')

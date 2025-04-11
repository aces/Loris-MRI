from datetime import datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.candidate as db_candidate
import lib.db.models.dicom_archive as db_dicom_archive
import lib.db.models.mri_protocol_group as db_mri_protocol_group
from lib.db.base import Base


class DbMriProtocolViolatedScan(Base):
    __tablename__ = 'mri_protocol_violated_scans'

    id                       : Mapped[int]             = mapped_column('ID', primary_key=True)
    candidate_id             : Mapped[int | None]      = mapped_column('CandidateID', ForeignKey('candidate.ID'))
    pscid                    : Mapped[str | None]      = mapped_column('PSCID')
    dicom_archive_id         : Mapped[int | None]      = mapped_column('TarchiveID', ForeignKey('tarchive.TarchiveID'))
    time_run                 : Mapped[datetime | None] = mapped_column('time_run')
    series_description       : Mapped[str | None]      = mapped_column('series_description')
    minc_location            : Mapped[str | None]      = mapped_column('minc_location')
    patient_name             : Mapped[str | None]      = mapped_column('PatientName')
    tr_range                 : Mapped[str | None]      = mapped_column('TR_range')
    te_range                 : Mapped[str | None]      = mapped_column('TE_range')
    ti_range                 : Mapped[str | None]      = mapped_column('TI_range')
    slice_thickness_range    : Mapped[str | None]      = mapped_column('slice_thickness_range')
    xspace_range             : Mapped[str | None]      = mapped_column('xspace_range')
    yspace_range             : Mapped[str | None]      = mapped_column('yspace_range')
    zspace_range             : Mapped[str | None]      = mapped_column('zspace_range')
    xstep_range              : Mapped[str | None]      = mapped_column('xstep_range')
    ystep_range              : Mapped[str | None]      = mapped_column('ystep_range')
    zstep_range              : Mapped[str | None]      = mapped_column('zstep_range')
    time_range               : Mapped[str | None]      = mapped_column('time_range')
    series_uid               : Mapped[str | None]      = mapped_column('SeriesUID')
    image_type               : Mapped[str | None]      = mapped_column('image_type')
    phase_encoding_direction : Mapped[str | None]      = mapped_column('PhaseEncodingDirection')
    echo_number              : Mapped[str | None]      = mapped_column('EchoNumber')
    protocol_group_id        : Mapped[int | None]      \
        = mapped_column('MriProtocolGroupID', ForeignKey('mri_protocol_group.MriProtocolGroupID'))

    candidate     : Mapped[Optional['db_candidate.DbCandidate']] \
        = relationship('DbCandidate', back_populates='violated_scans')
    archive       : Mapped[Optional['db_dicom_archive.DbDicomArchive']] \
        = relationship('DbDicomArchive', back_populates='violated_scans')
    protocol_group: Mapped['db_mri_protocol_group.DbMriProtocolGroup']\
        = relationship('DbMriProtocolGroup', back_populates='violated_scans')

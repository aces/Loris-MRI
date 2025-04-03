from datetime import datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.candidate as db_candidate
import lib.db.models.dicom_archive as db_dicom_archive
import lib.db.models.mri_protocol_checks as db_mri_protocol_checks
import lib.db.models.mri_protocol_checks_group as db_mri_protocol_checks_group
import lib.db.models.mri_scan_type as db_mri_scan_type
from lib.db.base import Base


class DbMriViolationsLog(Base):
    __tablename__ = 'mri_violations_log'

    id                          : Mapped[int]              = mapped_column('LogID', primary_key=True)
    time_run                    : Mapped[datetime]         = mapped_column('TimeRun')
    series_uid                  : Mapped[str | None]       = mapped_column('SeriesUID')
    dicom_archive_id            : Mapped[int | None]       \
        = mapped_column('TarchiveID', ForeignKey('tarchive.TarchiveID'))
    minc_file                   : Mapped[str | None]       = mapped_column('MincFile')
    PatientName                 : Mapped[str | None]       = mapped_column('PatientName')
    candidate_id                : Mapped[int | None]       = mapped_column('CandidateID', ForeignKey('candidate.ID'))
    visit_label                 : Mapped[str | None]       = mapped_column('Visit_label')
    check_id                    : Mapped[int | None]       = mapped_column('CheckID')
    mri_scan_type_id            : Mapped[int | None]       \
        = mapped_column('MriScanTypeID', ForeignKey('mri_scan_type.MriScanTypeID'))
    severity                    : Mapped[str | None]       = mapped_column('Severity')
    header                      : Mapped[str | None]       = mapped_column('Header')
    value                       : Mapped[str | None]       = mapped_column('Value')
    valid_range                 : Mapped[str | None]       = mapped_column('ValidRange')
    valid_regex                 : Mapped[str | None]       = mapped_column('ValidRegex')
    echo_time                   : Mapped[float | None]     = mapped_column('EchoTime')
    phase_encoding_direction    : Mapped[str | None]       = mapped_column('PhaseEncodingDirection')
    echo_number                 : Mapped[str | None]       = mapped_column('EchoNumber')
    mri_protocol_checks_group_id: Mapped[int | None]       \
        = mapped_column('MriProtocolChecksGroupID', ForeignKey('mri_protocol_checks_group.MriProtocolChecksGroupID'))

    archive              : Mapped[Optional['db_dicom_archive.DbDicomArchive']] \
        = relationship('DbDicomArchive', back_populates='violations_log')
    candidate            : Mapped[Optional['db_candidate.DbCandidate']] \
        = relationship('DbCandidate', back_populates='violations_log')
    scan_type            : Mapped[Optional['db_mri_scan_type.DbMriScanType']] \
        = relationship('DbMriScanType', back_populates='violations_log')
    protocol_checks_group: Mapped[Optional['db_mri_protocol_checks_group.DbMriProtocolChecksGroup']] \
        = relationship('DbMriProtocolChecksGroup', back_populates='violations_log')

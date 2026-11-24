from datetime import datetime
from pathlib import Path

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.candidate as db_candidate
import lib.db.models.dicom_archive as db_dicom_archive
import lib.db.models.mri_protocol_check_group as db_mri_protocol_check_group
import lib.db.models.mri_scan_type as db_mri_scan_type
from lib.db.base import Base
from lib.db.decorators.string_path import StringPath


class DbMriScanValidationError(Base):
    __tablename__ = 'mri_violations_log'

    id                      : Mapped[int]              = mapped_column('LogID', primary_key=True)
    time_run                : Mapped[datetime]         = mapped_column('TimeRun', default=datetime.now)
    series_uid              : Mapped[str | None]       = mapped_column('SeriesUID')
    dicom_archive_id        : Mapped[int | None]       \
        = mapped_column('TarchiveID', ForeignKey('tarchive.TarchiveID'))
    file_path               : Mapped[Path | None]      = mapped_column('MincFile', StringPath)
    patient_name            : Mapped[str | None]       = mapped_column('PatientName')
    candidate_id            : Mapped[int | None]       = mapped_column('CandidateID', ForeignKey('candidate.ID'))
    visit_label             : Mapped[str | None]       = mapped_column('Visit_label')
    check_id                : Mapped[int | None]       = mapped_column('CheckID')
    scan_type_id            : Mapped[int | None]       \
        = mapped_column('MriScanTypeID', ForeignKey('mri_scan_type.MriScanTypeID'))
    severity                : Mapped[str | None]       = mapped_column('Severity')
    header                  : Mapped[str | None]       = mapped_column('Header')
    value                   : Mapped[str | None]       = mapped_column('Value')
    valid_range             : Mapped[str | None]       = mapped_column('ValidRange')
    valid_regex             : Mapped[str | None]       = mapped_column('ValidRegex')
    echo_time               : Mapped[float | None]     = mapped_column('EchoTime')
    phase_encoding_direction: Mapped[str | None]       = mapped_column('PhaseEncodingDirection')
    echo_number             : Mapped[str | None]       = mapped_column('EchoNumber')
    protocol_check_group_id : Mapped[int | None]       \
        = mapped_column('MriProtocolChecksGroupID', ForeignKey('mri_protocol_checks_group.MriProtocolChecksGroupID'))

    dicom_archive        : Mapped['db_dicom_archive.DbDicomArchive | None'] \
        = relationship('DbDicomArchive', back_populates='mri_scan_validation_errors')
    candidate            : Mapped['db_candidate.DbCandidate | None'] \
        = relationship('DbCandidate', back_populates='mri_scan_validation_errors')
    scan_type            : Mapped['db_mri_scan_type.DbMriScanType | None'] \
        = relationship('DbMriScanType', back_populates='scan_validation_errors')
    protocol_check_group : Mapped['db_mri_protocol_check_group.DbMriProtocolCheckGroup | None'] \
        = relationship('DbMriProtocolCheckGroup', back_populates='scan_validation_errors')

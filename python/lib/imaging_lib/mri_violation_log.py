from datetime import datetime
from pathlib import Path

from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.mri_scan_type import DbMriScanType
from lib.db.models.mri_violation_log import DbMriViolationLog
from lib.db.models.session import DbSession
from lib.db.queries.mri_violation_log import try_get_matching_mri_violation_log
from lib.env import Env


def register_mri_violation_log(
    env: Env,
    session: DbSession,
    dicom_archive: DbDicomArchive | None,
    scan_type: DbMriScanType,
    file_path: Path,
    patient_name: str | None,
    series_uid: str | None,
    echo_time: float | None,
    echo_number: str,
    phase_encoding_direction: str | None,
    protocol_check_group_id: int | None,
    check_id: int | None,
    severity: str,
    header: str,
    value: str | None,
    valid_range: str | None,
    valid_regex: str | None,
) -> DbMriViolationLog:
    """
    Register an MRI violation log in the database using the provided information, or return
    the existing log if it already exists.
    """

    dicom_archive_id = dicom_archive.id if dicom_archive is not None else None

    violation = try_get_matching_mri_violation_log(
        env.db, dicom_archive_id, series_uid, echo_time, echo_number, phase_encoding_direction,
        scan_type.id, severity, header, value, valid_range, valid_regex,
    )

    if violation is not None:
        return violation

    violation = DbMriViolationLog(
        time_run                 = datetime.now(),
        dicom_archive_id         = dicom_archive_id,
        candidate_id             = session.candidate_id,
        visit_label              = session.visit_label,
        scan_type_id             = scan_type.id,
        file_path                = file_path,
        patient_name             = patient_name,
        series_uid               = series_uid,
        echo_time                = echo_time,
        echo_number              = echo_number,
        phase_encoding_direction = phase_encoding_direction,
        protocol_check_group_id  = protocol_check_group_id,
        check_id                 = check_id,
        severity                 = severity,
        header                   = header,
        value                    = value,
        valid_range              = valid_range,
        valid_regex              = valid_regex,
    )

    env.db.add(violation)
    env.db.flush()

    return violation

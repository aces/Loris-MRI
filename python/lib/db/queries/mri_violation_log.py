from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_violation_log import DbMriViolationLog


def get_violations_log_with_unique_series_combination(
    db: Database,
    series_uid: str,
    echo_time: str | None,
    echo_number: str | None,
    phase_encoding_direction: str | None
) -> Sequence[DbMriViolationLog]:
    """
    Get all violations log from the database using the file's SeriesInstanceUID,
    echo time, echo number and phase encoding direction.
    """

    return db.execute(select(DbMriViolationLog)
        .where(DbMriViolationLog.series_uid == series_uid)
        .where(DbMriViolationLog.echo_time == echo_time)
        .where(DbMriViolationLog.echo_number == echo_number)
        .where(DbMriViolationLog.phase_encoding_direction == phase_encoding_direction)
    ).scalars().all()


def try_get_matching_mri_violation_log(
    db: Database,
    dicom_archive_id: int | None,
    series_uid: str | None,
    echo_time: float | None,
    echo_number: str,
    phase_encoding_direction: str | None,
    scan_type_id: int,
    severity: str,
    header: str,
    value: str | None,
    valid_range: str | None,
    valid_regex: str | None,
) -> DbMriViolationLog | None:
    """
    Get an MRI violation log from the database using the provided information, or return `None`
    if no violation log is found.
    """

    return db.execute(select(DbMriViolationLog)
        .where(DbMriViolationLog.dicom_archive_id == dicom_archive_id)
        .where(DbMriViolationLog.series_uid == series_uid)
        .where(DbMriViolationLog.echo_time == echo_time)
        .where(DbMriViolationLog.echo_number == echo_number)
        .where(DbMriViolationLog.phase_encoding_direction == phase_encoding_direction)
        .where(DbMriViolationLog.scan_type_id == scan_type_id)
        .where(DbMriViolationLog.severity == severity)
        .where(DbMriViolationLog.header == header)
        .where(DbMriViolationLog.value == value)
        .where(DbMriViolationLog.valid_range == valid_range)
        .where(DbMriViolationLog.valid_regex == valid_regex)
    ).scalars().first()

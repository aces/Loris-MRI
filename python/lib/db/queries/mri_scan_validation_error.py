from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_scan_validation_error import DbMriScanValidationError


def get_scan_validation_errors_with_unique_series_combination(
    db: Database,
    series_uid: str,
    echo_time: str | None,
    echo_number: str | None,
    phase_encoding_direction: str | None
) -> Sequence[DbMriScanValidationError]:
    """
    Get all MRI scan validation errors from the database using the file's SeriesInstanceUID,
    echo time, echo number and phase encoding direction.
    """

    return db.execute(select(DbMriScanValidationError)
        .where(DbMriScanValidationError.series_uid == series_uid)
        .where(DbMriScanValidationError.echo_time == echo_time)
        .where(DbMriScanValidationError.echo_number == echo_number)
        .where(DbMriScanValidationError.phase_encoding_direction == phase_encoding_direction)
    ).scalars().all()


def try_get_matching_mri_scan_validation_error(
    db: Database,
    dicom_archive_id: int | None,
    series_uid: str | None,
    echo_time: float | None,
    echo_number: str | None,
    phase_encoding_direction: str | None,
    scan_type_id: int,
    severity: str,
    header: str,
    value: str | None,
    valid_range: str | None,
    valid_regex: str | None,
) -> DbMriScanValidationError | None:
    """
    Get an MRI scan validation error from the database using the provided information,
    or return `None` if no scan validation error is found.
    """

    return db.execute(select(DbMriScanValidationError)
        .where(DbMriScanValidationError.dicom_archive_id == dicom_archive_id)
        .where(DbMriScanValidationError.series_uid == series_uid)
        .where(DbMriScanValidationError.echo_time == echo_time)
        .where(DbMriScanValidationError.echo_number == echo_number)
        .where(DbMriScanValidationError.phase_encoding_direction == phase_encoding_direction)
        .where(DbMriScanValidationError.scan_type_id == scan_type_id)
        .where(DbMriScanValidationError.severity == severity)
        .where(DbMriScanValidationError.header == header)
        .where(DbMriScanValidationError.value == value)
        .where(DbMriScanValidationError.valid_range == valid_range)
        .where(DbMriScanValidationError.valid_regex == valid_regex)
    ).scalars().first()

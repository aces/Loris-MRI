from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_scan_classification_error import DbMriScanClassificationError


def get_scan_classification_errors_with_unique_series_combination(
    db: Database,
    series_uid: str,
    echo_time: str | None,
    echo_number: str | None,
    phase_encoding_direction: str | None
) -> Sequence[DbMriScanClassificationError]:
    """
    Get all MRI scan classification errors from the database using the file's SeriesInstanceUID,
    echo time, echo number and phase encoding direction.
    """

    return db.execute(select(DbMriScanClassificationError)
        .where(DbMriScanClassificationError.series_uid == series_uid)
        .where(DbMriScanClassificationError.te_range == echo_time)
        .where(DbMriScanClassificationError.echo_number == echo_number)
        .where(DbMriScanClassificationError.phase_encoding_direction == phase_encoding_direction)
    ).scalars().all()


def try_get_matching_mri_scan_classification_error(
    db: Database,
    dicom_archive_id: int | None,
    series_uid: str | None,
    echo_time: str | None,
    echo_number: str | None,
    phase_encoding_direction: str | None,
) -> DbMriScanClassificationError | None:
    """
    Get an MRI scan classification error from the database using the provided information, or return
    `None` if no error is found.
    """

    return db.execute(select(DbMriScanClassificationError)
        .where(DbMriScanClassificationError.dicom_archive_id == dicom_archive_id)
        .where(DbMriScanClassificationError.series_uid == series_uid)
        .where(DbMriScanClassificationError.te_range == echo_time)
        .where(DbMriScanClassificationError.echo_number == echo_number)
        .where(DbMriScanClassificationError.phase_encoding_direction == phase_encoding_direction)
    ).scalars().first()

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_scan_identification_error import DbMriScanIdentificationError


def try_get_matching_mri_scan_identification_error(
    db: Database,
    dicom_archive_id: int | None,
    series_uid: str | None,
    echo_time: float | None,
    patient_name: str | None,
    reason: str,
) -> DbMriScanIdentificationError | None:
    """
    Get an MRI scan identification error from the database using the provided information, or return
    `None` if no candidate error is found.
    """

    return db.execute(select(DbMriScanIdentificationError)
        .where(DbMriScanIdentificationError.dicom_archive_id == dicom_archive_id)
        .where(DbMriScanIdentificationError.series_uid == series_uid)
        .where(DbMriScanIdentificationError.echo_time == echo_time)
        .where(DbMriScanIdentificationError.patient_name == patient_name)
        .where(DbMriScanIdentificationError.reason == reason)
    ).scalars().first()

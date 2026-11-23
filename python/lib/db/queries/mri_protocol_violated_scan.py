from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_protocol_violated_scan import DbMriProtocolViolatedScan


def get_protocol_violated_scans_with_unique_series_combination(
    db: Database,
    series_uid: str,
    echo_time: str | None,
    echo_number: str | None,
    phase_encoding_direction: str | None
) -> Sequence[DbMriProtocolViolatedScan]:
    """
    Get all protocol violated scans from the database using the file's SeriesInstanceUID,
    echo time, echo number and phase encoding direction.
    """

    return db.execute(select(DbMriProtocolViolatedScan)
        .where(DbMriProtocolViolatedScan.series_uid == series_uid)
        .where(DbMriProtocolViolatedScan.te_range == echo_time)
        .where(DbMriProtocolViolatedScan.echo_number == echo_number)
        .where(DbMriProtocolViolatedScan.phase_encoding_direction == phase_encoding_direction)
    ).scalars().all()


def try_get_matching_mri_protocol_violated_scan(
    db: Database,
    dicom_archive_id: int | None,
    series_uid: str | None,
    echo_time: str | None,
    echo_number: str | None,
    phase_encoding_direction: str | None,
) -> DbMriProtocolViolatedScan | None:
    """
    Get a protocol violated scan from the database using the provided information, or return
    `None` if no scan is found.
    """

    return db.execute(select(DbMriProtocolViolatedScan)
        .where(DbMriProtocolViolatedScan.dicom_archive_id == dicom_archive_id)
        .where(DbMriProtocolViolatedScan.series_uid == series_uid)
        .where(DbMriProtocolViolatedScan.te_range == echo_time)
        .where(DbMriProtocolViolatedScan.echo_number == echo_number)
        .where(DbMriProtocolViolatedScan.phase_encoding_direction == phase_encoding_direction)
    ).scalars().first()

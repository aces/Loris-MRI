from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_protocol_violated_scan import DbMriProtocolViolatedScan


def try_get_protocol_violated_scans_with_unique_series_combination(
        db: Database,
        series_uid: str,
        echo_time: str | None,
        echo_number: str | None,
        phase_encoding_direction: str | None
) -> DbMriProtocolViolatedScan | None:
    """
    Get the protocol violated scans from the database using its SeriesInstanceUID, or return `None` if
    no protocol violated scan was found.
    """

    return db.execute(select(DbMriProtocolViolatedScan)
        .where(DbMriProtocolViolatedScan.series_uid == series_uid)
        .where(DbMriProtocolViolatedScan.te_range == echo_time)
        .where(DbMriProtocolViolatedScan.echo_number == echo_number)
        .where(DbMriProtocolViolatedScan.phase_encoding_direction == phase_encoding_direction)
    ).scalar_one_or_none()

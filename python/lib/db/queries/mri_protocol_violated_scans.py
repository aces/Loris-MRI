from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_protocol_violated_scans import DbMriProtocolViolatedScans


def try_get_protocol_violated_scans_with_unique_series_combination(
        db: Database,
        series_uid: str,
        echo_time: str | None,
        echo_number: str | None,
        phase_encoding_direction: str | None
) -> DbMriProtocolViolatedScans | None:
    """
    Get a protocol violated scans from the database using its SeriesInstanceUID, or return `None` if
    no protocol violated scan was found.
    """

    return db.execute(select(DbMriProtocolViolatedScans)
        .where(DbMriProtocolViolatedScans.series_uid == series_uid)
        .where(DbMriProtocolViolatedScans.te_range == echo_time)
        .where(DbMriProtocolViolatedScans.echo_number == echo_number)
        .where(DbMriProtocolViolatedScans.phase_encoding_direction == phase_encoding_direction)
    ).scalar_one_or_none()


from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_protocol_violated_scans import DbMriProtocolViolatedScans


def try_get_protocol_violated_scans_with_series_uid(db: Database, series_uid: str) -> DbMriProtocolViolatedScans | None:
    """
    Get a protocol violated scans from the database using its SeriesInstanceUID, or return `None` if
    no protocol violated scan was found.
    """

    return db.execute(select(DbMriProtocolViolatedScans)
        .where(DbMriProtocolViolatedScans.series_uid == series_uid)
    ).scalar_one_or_none()

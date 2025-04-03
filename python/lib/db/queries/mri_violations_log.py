from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_violations_log import DbMriViolationsLog


def try_get_violations_log_with_unique_series_combination(
        db: Database,
        series_uid: str,
        echo_time: str | None,
        echo_number: str | None,
        phase_encoding_direction: str | None
) -> DbMriViolationsLog | None:
    """
    Get the violations log from the database using its SeriesInstanceUID, or return `None` if
    no violations log was found.
    """

    return db.execute(select(DbMriViolationsLog)
        .where(DbMriViolationsLog.series_uid == series_uid)
        .where(DbMriViolationsLog.echo_time == echo_time)
        .where(DbMriViolationsLog.echo_number == echo_number)
        .where(DbMriViolationsLog.phase_encoding_direction == phase_encoding_direction)
    ).scalar_one_or_none()

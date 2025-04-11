from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_violation_log import DbMriViolationLog


def try_get_violations_log_with_unique_series_combination(
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

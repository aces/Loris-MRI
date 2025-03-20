from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.cohort import DbCohort


def try_get_cohort_with_name(db: Database, name: str) -> Optional[DbCohort]:
    """
    Try to get a cohort from the database using its name, or return `None` if no cohort is found.
    """

    return db.execute(select(DbCohort)
        .where(DbCohort.name == name)
    ).scalar_one_or_none()

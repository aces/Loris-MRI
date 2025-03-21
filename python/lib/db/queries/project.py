from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.project_cohort import DbProjectCohort


def try_get_project_cohort_with_project_id_cohort_id(db: Database, project_id: int, cohort_id: int):
    """
    Get a project cohort relation from the database using its project ID and candidate ID, or
    return `None` if no relation is found.
    """

    return db.execute(select(DbProjectCohort)
        .where(DbProjectCohort.project_id == project_id)
        .where(DbProjectCohort.cohort_id == cohort_id)
    ).scalar_one_or_none()

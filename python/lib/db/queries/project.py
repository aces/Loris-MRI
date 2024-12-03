
from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.project import DbProject
from lib.db.models.project_cohort import DbProjectCohort


def try_get_project_with_id(db: Database, id: int) -> DbProject | None:
    """
    Try to get a project from the database using its ID, or return `None` if no project is found.
    """

    return db.execute(select(DbProject)
        .where(DbProject.id == id)
    ).scalar_one_or_none()


def try_get_project_with_name(db: Database, name: str) -> DbProject | None:
    """
    Try to get a project from the database using its name, or return `None` if no project is found.
    """

    return db.execute(select(DbProject)
        .where(DbProject.name == name)
    ).scalar_one_or_none()


def try_get_project_with_alias(db: Database, alias: str) -> DbProject | None:
    """
    Try to get a project from the database using its alias, or return `None` if no project is found.
    """

    return db.execute(select(DbProject)
        .where(DbProject.alias == alias)
    ).scalar_one_or_none()


def try_get_project_cohort_with_project_id_cohort_id(
    db: Database,
    project_id: int,
    cohort_id: int,
) -> DbProjectCohort | None:
    """
    Get a project cohort relation from the database using its project ID and candidate ID, or
    return `None` if no relation is found.
    """

    return db.execute(select(DbProjectCohort)
        .where(DbProjectCohort.project_id == project_id)
        .where(DbProjectCohort.cohort_id == cohort_id)
    ).scalar_one_or_none()

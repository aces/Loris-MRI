from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.visit import DbVisit
from lib.db.models.visit_window import DbVisitWindow


def try_get_visit_with_visit_label(db: Database, visit_label: str) -> DbVisit | None:
    """
    Get a visit from the database using its visit label, or return `None` if no visit is found.
    """

    return db.execute(select(DbVisit)
        .where(DbVisit.label == visit_label)
    ).scalar_one_or_none()


def try_get_visit_window_with_visit_label(db: Database, visit_label: str) -> DbVisitWindow | None:
    """
    Get a visit window from the database using its visit label, or return `None` if no visit
    window is found.
    """

    return db.execute(select(DbVisitWindow)
        .where(DbVisitWindow.visit_label == visit_label)
    ).scalar_one_or_none()

from sqlalchemy import select
from sqlalchemy.orm import Session as Database
from lib.db.model.visit_window import DbVisitWindow


def try_get_visit_window_with_visit_label(db: Database, visit_label: str):
    """
    Get a visit window from the database using its visit label, or return `None` if no visit
    window is found.
    """

    query = select(DbVisitWindow).where(DbVisitWindow.visit_label == visit_label)
    return db.execute(query).scalar_one_or_none()

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.model.candidate import DbCandidate
from lib.db.model.session import DbSession
from lib.db.model.site import DbSite


def try_get_site_with_psc_id_visit_label(db: Database, psc_id: str, visit_label: str):
    """
    Get a session from the database using its candidate CandID and visit label, or return `None`
    if no session is found.
    """

    return db.execute(select(DbSite)
        .join(DbSession.site)
        .join(DbSession.candidate)
        .where(DbCandidate.psc_id == psc_id)
        .where(DbSession.visit_label == visit_label)
    ).scalar_one_or_none()

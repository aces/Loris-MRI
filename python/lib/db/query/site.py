from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.model.candidate import DbCandidate
from lib.db.model.session import DbSession
from lib.db.model.site import DbSite


def try_get_site_with_cand_id_visit_label(db: Database, cand_id: int, visit_label: str):
    """
    Get a site from the database using a candidate CandID and visit label, or return `None` if no
    site is found.
    """

    return db.execute(select(DbSite)
        .join(DbSession.site)
        .join(DbSession.candidate)
        .where(DbCandidate.cand_id == cand_id)
        .where(DbSession.visit_label == visit_label)
    ).scalar_one_or_none()

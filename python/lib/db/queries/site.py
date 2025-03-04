from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.candidate import DbCandidate
from lib.db.models.session import DbSession
from lib.db.models.site import DbSite


def try_get_site_with_cand_id_visit_label(db: Database, cand_id: int, visit_label: str) -> DbSite | None:
    """
    Get a site from the database using a candidate CandID and visit label, or return `None` if no
    site is found.
    """

    return db.execute(select(DbSite)
        .join(DbSession.site)
        .join(DbSession.candidate)
        .where(DbSession.visit_label == visit_label)
        .where(DbCandidate.cand_id == cand_id)
    ).scalar_one_or_none()


def get_all_sites(db: Database) -> Sequence[DbSite]:
    """
    Get a sequence of all sites from the database.
    """

    return db.execute(select(DbSite)).scalars().all()

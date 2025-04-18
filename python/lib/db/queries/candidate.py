from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.candidate import DbCandidate


def try_get_candidate_with_cand_id(db: Database, cand_id: int) -> DbCandidate | None:
    """
    Get a candidate from the database using its CandID, or return `None` if no candidate is found.
    """

    return db.execute(select(DbCandidate)
        .where(DbCandidate.cand_id == cand_id)
    ).scalar_one_or_none()


def try_get_candidate_with_psc_id(db: Database, psc_id: str) -> DbCandidate | None:
    """
    Get a candidate from the database using its PSCID, or return `None` if no candidate is found.
    """

    return db.execute(select(DbCandidate)
        .where(DbCandidate.psc_id == psc_id)
    ).scalar_one_or_none()

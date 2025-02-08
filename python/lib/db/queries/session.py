
from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.candidate import DbCandidate
from lib.db.models.session import DbSession


def try_get_session_with_cand_id_visit_label(db: Database, cand_id: int, visit_label: str):
    """
    Get a session from the database using its candidate CandID and visit label, or return `None`
    if no session is found.
    """

    return db.execute(select(DbSession)
        .join(DbSession.candidate)
        .where(DbSession.visit_label == visit_label)
        .where(DbCandidate.cand_id == cand_id)
    ).scalar_one_or_none()


def try_get_session_with_id(db: Database, session_id: int):
    """
    Get a session from the database using its ID, or return `None` if no session is found.
    """

    return db.execute(select(DbSession)
        .where(DbSession.id == session_id)
    ).scalar_one_or_none()

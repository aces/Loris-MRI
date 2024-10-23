
from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.model.session import DbSession


def try_get_session_with_cand_id_visit_label(db: Database, cand_id: int, visit_label: str):
    """
    Get a session from the database using its candidate CandID and visit label, or return `None`
    if no session is found.
    """

    return db.execute(select(DbSession)
        .where(DbSession.cand_id == cand_id)
        .where(DbSession.visit_label == visit_label)
    ).scalar_one_or_none()
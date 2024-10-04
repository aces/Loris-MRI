from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from lib.db.base import Base


def create_test_database():
    """
    Create an empty in-memory database to be used for unit tests.
    """

    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)
    return Session(engine)

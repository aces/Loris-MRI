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


def get_integration_database_engine():
    return create_engine('mysql+mysqldb://SQLTestUser:TestPassword@db:3306/LorisTest')

import os
import sys
from typing import cast

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session

from lib.db.base import Base
from lib.db.connect import connect_to_database


def create_test_database():
    """
    Create an empty in-memory database to be used for unit tests.
    """

    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)
    return Session(engine)


def get_integration_database_engine():
    """
    Get an SQLAlchemy engine for the integration testing database using the configuration from the
    Python configuration file.
    """

    config_file = os.path.join(os.environ['LORIS_CONFIG'], '.loris_mri', 'database_config.py')
    sys.path.append(os.path.dirname(config_file))
    config = __import__(os.path.basename(config_file[:-3]))
    session = connect_to_database(config.mysql)
    return cast(Engine, session.get_bind())

from sqlalchemy import URL, create_engine
from sqlalchemy.orm import Session

from lib.config_file import DatabaseConfig


def connect_to_database(config: DatabaseConfig):
    """
    Connect to the database and get an SQLAlchemy session to interract with it using the provided
    credentials.
    """

    # The SQLAlchemy URL object notably escapes special characters in the configuration attributes
    url = URL.create(
        drivername = 'mysql+mysqldb',
        host       = config.host,
        port       = config.port,
        username   = config.username,
        password   = config.password,
        database   = config.database,
    )

    engine = create_engine(url)
    return Session(engine)

from urllib.parse import quote

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from lib.config_file import DatabaseConfig


def connect_to_database(config: DatabaseConfig):
    """
    Connect to the database and get an SQLAlchemy session to interract with it using the provided
    credentials.
    """

    host     = config.host
    port     = config.port
    username = quote(config.username)
    password = quote(config.password)
    database = config.database
    engine = create_engine(f'mysql+mysqldb://{username}:{password}@{host}:{port}/{database}')
    return Session(engine)

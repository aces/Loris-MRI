from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from lib.dataclass.config import DatabaseConfig


def connect_to_database(credentials: DatabaseConfig):
    """
    Connect to the database and get an SQLAlchemy session to interract with it using the provided
    credentials.
    """

    host     = credentials.host
    port     = credentials.port
    username = credentials.username
    password = credentials.password
    database = credentials.database
    engine = create_engine(f'mariadb+mysqlconnector://{username}:{password}@{host}:{port}/{database}')
    return Session(engine)

from sqlalchemy import URL, create_engine

from lib.config_file import DatabaseConfig


def get_database_engine(config: DatabaseConfig):
    """
    Connect to the database and return an SQLAlchemy engine using the provided credentials.
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

    return create_engine(url)

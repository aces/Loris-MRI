from sqlalchemy import URL, create_engine

from lib.config_file import DatabaseConfig


def get_database_engine(config: DatabaseConfig):
    """
    Connect to the database and return an SQLAlchemy engine using the provided credentials.
    """

    # The SQLAlchemy URL object notably escapes special characters in the configuration attributes.
    url = URL.create(
        drivername = 'mysql+mysqldb',
        host       = config.host,
        port       = config.port,
        username   = config.username,
        password   = config.password,
        database   = config.database,
    )

    # 'READ COMMITED' means that the records read in a session can be modified by other sessions
    # (such as subscripts or other scripts) during this session's lifetime.
    return create_engine(url, isolation_level='READ COMMITTED')

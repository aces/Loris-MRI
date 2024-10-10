from typing import Any
from urllib.parse import quote

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

default_port = 3306


def connect_to_db(credentials: dict[str, Any]):
    host     = credentials['host']
    port     = credentials['port']
    username = quote(credentials['username'])
    password = quote(credentials['passwd'])
    database = credentials['database']
    port     = int(port) if port else default_port
    engine = create_engine(f'mysql+mysqldb://{username}:{password}@{host}:{port}/{database}')
    return Session(engine)

from typing import Any
from sqlalchemy import create_engine
from sqlalchemy.orm import Session


default_port = 3306


def connect_to_db(credentials: dict[str, Any]) -> Session:
    host     = credentials['host']
    port     = credentials['port']
    username = credentials['username']
    password = credentials['passwd']
    database = credentials['database']
    port     = int(port) if port else default_port
    engine = create_engine(f'mariadb+mysqlconnector://{username}:{password}@{host}:{port}/{database}')
    return Session(engine)

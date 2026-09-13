from collections.abc import Iterator
from pathlib import Path
from types import SimpleNamespace

import pytest
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session

from lib.db.base import Base
from lib.env import Env


@pytest.fixture
def db_engine() -> Iterator[Engine]:
    """
    Create an in-memory SQLite database engine based on the ORM schema.
    """

    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)

    yield engine

    engine.dispose()


@pytest.fixture
def db(db_engine: Engine) -> Iterator[Session]:
    """
    Create an in-memory SQLite database session to run a unit test.
    """

    with Session(db_engine) as db:
        yield db
        db.rollback()


@pytest.fixture
def env(db_engine: Engine, db: Session, tmp_path: Path) -> Env:
    """
    Create a LORIS environment with an in-memory SQLite database to run a unit test.
    """

    return Env(
        db_engine     = db_engine,
        db            = db,
        script_name   = 'pytest',
        config_info   = SimpleNamespace(),
        tmp_dir_path  = tmp_path,
        log_file_path = tmp_path / 'test.log',
        verbose       = False,
        cleanups      = [],
    )

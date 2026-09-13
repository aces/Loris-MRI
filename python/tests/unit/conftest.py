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
    Create an in-memory SQLite database containing the ORM schema.
    """

    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)

    yield engine

    engine.dispose()


@pytest.fixture
def db(db_engine: Engine) -> Iterator[Session]:
    """
    Create an in-memory SQLite database session for a test.
    """

    with Session(db_engine) as db:
        yield db
        db.rollback()


@pytest.fixture
def env(db_engine: Engine, db: Session, tmp_path: Path) -> Env:
    """
    Create a LORIS execution environment for a test.
    """

    return Env(
        db_engine     = db_engine,
        db            = db,
        script_name   ='pytest',
        config_info   =SimpleNamespace(),
        tmp_dir_path  =tmp_path,
        log_file_path =tmp_path / 'test.log',
        verbose       = False,
        cleanups      = [],
    )

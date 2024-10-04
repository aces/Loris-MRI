from dataclasses import dataclass

import pytest
from sqlalchemy.orm import Session as Database

from lib.db.model.visit_window import DbVisitWindow
from lib.db.query.visit import try_get_visit_window_with_visit_label
from tests.util.database import create_test_database


@dataclass
class Setup:
    db: Database
    visit_window_1: DbVisitWindow
    visit_window_2: DbVisitWindow


@pytest.fixture
def setup():
    db = create_test_database()

    visit_window_1 = DbVisitWindow(
        visit_label = 'V1'
    )

    visit_window_2 = DbVisitWindow(
        visit_label = 'V2'
    )

    db.add(visit_window_1)
    db.add(visit_window_2)

    return Setup(db, visit_window_1, visit_window_2)


def test_try_get_visit_window_with_visit_label_some(setup: Setup):
    visit_window = try_get_visit_window_with_visit_label(setup.db, 'V1')
    assert visit_window is setup.visit_window_1


def test_try_get_visit_window_with_visit_label_none(setup: Setup):
    visit_window = try_get_visit_window_with_visit_label(setup.db, 'V3')
    assert visit_window is None

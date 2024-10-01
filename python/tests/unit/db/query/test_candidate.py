from dataclasses import dataclass

import pytest
from sqlalchemy.orm import Session as Database

from lib.db.model.candidate import DbCandidate
from lib.db.query.candidate import try_get_candidate_with_cand_id
from tests.util.database import create_test_database


@dataclass
class Setup:
    db: Database
    candidate_1: DbCandidate
    candidate_2: DbCandidate


@pytest.fixture
def setup():
    db = create_test_database()

    candidate_1 = DbCandidate(
        cand_id = 111111,
        psc_id='DCC001',
        registration_site_id = 1,
        registration_project_id = 1,
        active = True,
        user_id = 'admin',
        test_date = 0,
        entity_type = 'human',
    )

    candidate_2 = DbCandidate(
        cand_id = 222222,
        psc_id='DCC002',
        registration_site_id = 1,
        registration_project_id = 1,
        active = True,
        user_id = 'admin',
        test_date = 0,
        entity_type = 'human',
    )

    db.add(candidate_1)
    db.add(candidate_2)

    return Setup(db, candidate_1, candidate_2)


def test_try_get_candidate_with_cand_id_some(setup: Setup):
    candidate = try_get_candidate_with_cand_id(setup.db, 111111)
    assert candidate is setup.candidate_1


def test_try_get_candidate_with_cand_id_none(setup: Setup):
    candidate = try_get_candidate_with_cand_id(setup.db, 333333)
    assert candidate is None

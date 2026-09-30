from sqlalchemy.orm import Session as Database

from lib.db.models.user import DbUser
from lib.db.queries.user import try_get_user_with_id, try_get_user_with_username


def test_try_get_user_with_id_and_username(db: Database):
    user = DbUser(id=123, username='test_user', email='test@example.com')
    db.add(user)

    assert try_get_user_with_id(db, 123) is user
    assert try_get_user_with_username(db, 'test_user') is user


def test_try_get_user_returns_none(db: Database):
    assert try_get_user_with_id(db, 123) is None
    assert try_get_user_with_username(db, 'missing') is None

from datetime import date, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.config import DbConfig
from lib.db.models.config_setting import DbConfigSetting
from lib.db.models.project import DbProject
from lib.db.models.site import DbSite
from lib.db.models.user import DbUser
from lib.db.models.user_login_history import DbUserLoginHistory
from lib.env import Env
from lib.user import (
    can_user_access_project,
    can_user_access_site,
    check_user_account_active,
    check_user_account_locked,
)

NOW = datetime(2026, 10, 10, 12)


def make_user(values: dict[str, Any] | None = None) -> DbUser:
    defaults = {
        'username': 'test_user',
        'email': 'test@example.com',
        'active': True,
        'pending_approval': False,
        'password_change_required': False,
    }
    return DbUser(**(defaults | (values or {})))


def set_database_time(monkeypatch: pytest.MonkeyPatch):
    def get_database_time(_: Database) -> datetime:
        return NOW

    monkeypatch.setattr('lib.user.get_database_time', get_database_time)


@pytest.mark.parametrize(('values', 'expected'), [
    ({}, True),
    ({'active': False}, False),
    ({'pending_approval': True}, False),
    ({'password_change_required': True}, False),
    ({'active_from': date(2026, 10, 10)}, True),
    ({'active_from': date(2026, 10, 11)}, False),
    ({'active_to': date(2026, 10, 10)}, True),
    ({'active_to': date(2026, 10, 9)}, False),
])
def test_check_user_account_active_dates_and_flags(
    env: Env,
    monkeypatch: pytest.MonkeyPatch,
    values: dict[str, Any],
    expected: bool,
):
    set_database_time(monkeypatch)

    assert check_user_account_active(env, make_user(values)) is expected


def test_check_user_account_active_deactivates_inactive_user(env: Env, monkeypatch: pytest.MonkeyPatch):
    set_database_time(monkeypatch)

    env.db.add(DbConfig(
        setting=DbConfigSetting(name='UserMaximumDaysInactive'),
        value='30',
    ))

    user = make_user()

    env.db.add_all([
        user,
        DbUserLoginHistory(
            username=user.username,
            success=True,
            login_timestamp=NOW - timedelta(days=31),
        ),
    ])

    assert not check_user_account_active(env, user)

    env.db.expire_all()

    assert not env.db.execute(select(DbUser)
        .where(DbUser.username == user.username)
    ).scalar_one().active


def test_check_user_account_active_keeps_first_time_user_active(env: Env, monkeypatch: pytest.MonkeyPatch):
    set_database_time(monkeypatch)

    env.db.add(DbConfig(
        setting=DbConfigSetting(name='UserMaximumDaysInactive'),
        value='30',
    ))

    assert check_user_account_active(env, make_user())


def test_check_user_account_active_at_inactivity_limit(env: Env, monkeypatch: pytest.MonkeyPatch):
    set_database_time(monkeypatch)

    env.db.add(DbConfig(
        setting=DbConfigSetting(name='UserMaximumDaysInactive'),
        value='30',
    ))

    env.db.add(DbUserLoginHistory(
        username='test_user',
        success=True,
        login_timestamp=NOW - timedelta(days=30),
    ))

    assert check_user_account_active(env, make_user())


def test_failed_login_does_not_reset_account_inactivity(env: Env, monkeypatch: pytest.MonkeyPatch):
    set_database_time(monkeypatch)

    env.db.add(DbConfig(
        setting=DbConfigSetting(name='UserMaximumDaysInactive'),
        value='30',
    ))

    user = make_user()
    env.db.add_all([
        user,
        DbUserLoginHistory(
            username=user.username,
            success=True,
            login_timestamp=NOW - timedelta(days=31),
        ),
        DbUserLoginHistory(
            username=user.username,
            success=False,
            login_timestamp=NOW - timedelta(days=1),
        ),
    ])

    assert not check_user_account_active(env, user)


def add_login_attempts(
    env: Env,
    count: int,
    username: str = 'test_user',
    ip_address: str = '192.0.2.1',
    success: bool = False,
    timestamp: datetime = NOW,
):
    env.db.add_all(
        DbUserLoginHistory(
            username=username,
            ip_address=ip_address,
            success=success,
            login_timestamp=timestamp,
        )
        for _ in range(count)
    )


@pytest.mark.parametrize(('count', 'minutes_ago', 'expected'), [
    (10, 10, False),
    (11, 10, True),
    (15, 30, False),
    (16, 30, True),
    (20, 61, False),
])
def test_check_user_account_locked_thresholds(
    env: Env,
    monkeypatch: pytest.MonkeyPatch,
    count: int,
    minutes_ago: int,
    expected: bool,
):
    set_database_time(monkeypatch)
    add_login_attempts(env, count, timestamp=NOW - timedelta(minutes=minutes_ago))

    assert check_user_account_locked(env, 'test_user', '192.0.2.1') is expected


def test_lockout_ignores_other_users_and_ips(env: Env, monkeypatch: pytest.MonkeyPatch):
    set_database_time(monkeypatch)
    add_login_attempts(env, 20, username='other_user')
    add_login_attempts(env, 20, ip_address='192.0.2.2')

    assert not check_user_account_locked(env, 'test_user', '192.0.2.1')


def test_successful_login_resets_lockout_window(env: Env, monkeypatch: pytest.MonkeyPatch):
    set_database_time(monkeypatch)
    add_login_attempts(env, 20, timestamp=NOW - timedelta(minutes=10))
    add_login_attempts(env, 1, success=True, timestamp=NOW - timedelta(minutes=5))

    assert not check_user_account_locked(env, 'test_user', '192.0.2.1')


def test_user_project_and_site_access(env: Env):
    project = DbProject(id=1, name='Project', alias='P')
    other_project = DbProject(id=2, name='Other project', alias='O')
    site = DbSite(id=1, name='Site', alias='S', mri_alias='S')
    other_site = DbSite(id=2, name='Other site', alias='O', mri_alias='O')
    user = make_user({'projects': [project], 'sites': [site]})

    assert can_user_access_project(env, user, project)
    assert not can_user_access_project(env, user, other_project)
    assert can_user_access_site(env, user, site)
    assert not can_user_access_site(env, user, other_site)

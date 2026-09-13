import pytest

from lib.config import get_user_maximum_days_inactive_config
from lib.db.models.config import DbConfig
from lib.db.models.config_setting import DbConfigSetting
from lib.env import Env


@pytest.mark.parametrize(('value', 'expected'), [
    (None, None),
    ('', None),
    ('invalid', None),
    ('0', None),
    ('30', 30),
])
def test_get_user_maximum_days_inactive_config(env: Env, value: str | None, expected: int | None):
    env.db.add(DbConfig(
        setting=DbConfigSetting(name='UserMaximumDaysInactive'),
        value=value,
    ))

    assert get_user_maximum_days_inactive_config(env) == expected


def test_get_user_maximum_days_inactive_config_missing(env: Env):
    assert get_user_maximum_days_inactive_config(env) is None

from lib.db.models.module import DbModule
from lib.env import Env
from lib.modules import is_module_active


def test_is_module_active(env: Env):
    env.db.add(DbModule(name='active_module', active=True))

    assert is_module_active(env, 'active_module')


def test_is_module_active_false_for_inactive_or_missing_module(env: Env):
    env.db.add(DbModule(name='inactive_module', active=False))

    assert not is_module_active(env, 'inactive_module')
    assert not is_module_active(env, 'missing_module')

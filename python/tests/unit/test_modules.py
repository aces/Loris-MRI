from lib.db.models.module import DbModule
from lib.env import Env
from lib.modules import module_is_active


def test_module_is_active(env: Env):
    env.db.add(DbModule(name='active_module', active=True))

    assert module_is_active(env, 'active_module')


def test_module_is_active_false_for_inactive_or_missing_module(env: Env):
    env.db.add(DbModule(name='inactive_module', active=False))

    assert not module_is_active(env, 'inactive_module')
    assert not module_is_active(env, 'missing_module')

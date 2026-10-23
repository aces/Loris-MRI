from collections.abc import Callable, Collection

import pytest

from lib.db.models.permission import DbPermission
from lib.db.models.user import DbUser
from lib.env import Env
from lib.permissions import (
    PermissionConfigurationError,
    user_has_all_permission_codes,
    user_has_all_permissions,
    user_has_any_permission,
    user_has_any_permission_codes,
    user_has_permission,
    user_has_permission_code,
)


def make_user_with_permissions(permission_codes: list[str]) -> DbUser:
    return DbUser(
        username='test_user',
        email='test@example.com',
        permissions=[DbPermission(code=code, description=code) for code in permission_codes],
    )


def register_permissions(env: Env, permission_codes: list[str]):
    env.db.add_all(DbPermission(code=code, description=code) for code in permission_codes)


def test_user_has_assigned_permission(env: Env):
    user = make_user_with_permissions(['permission_a'])
    env.db.add(user)

    assert user_has_permission(user, user.permissions[0])


def test_user_does_not_have_unassigned_valid_permission(env: Env):
    register_permissions(env, ['permission_a'])
    user = make_user_with_permissions([])

    assert not user_has_permission_code(env, user, 'permission_a')


def test_unknown_permission_raises(env: Env):
    with pytest.raises(PermissionConfigurationError, match='Invalid permission code unknown'):
        user_has_permission_code(env, make_user_with_permissions([]), 'unknown')


def test_superuser_grants_registered_permission(env: Env):
    user = make_user_with_permissions(['superuser'])
    env.db.add(user)
    register_permissions(env, ['permission_a'])

    assert user_has_permission_code(env, user, 'permission_a')


def test_superuser_cannot_use_unknown_permission(env: Env):
    user = make_user_with_permissions(['superuser'])
    env.db.add(user)

    with pytest.raises(PermissionConfigurationError, match='Invalid permission code unknown'):
        user_has_permission_code(env, user, 'unknown')


def test_user_has_any_permission(env: Env):
    user = make_user_with_permissions(['permission_a'])
    env.db.add(user)
    register_permissions(env, ['permission_b'])

    assert user_has_any_permission_codes(env, user, ['permission_a', 'permission_b'])
    assert not user_has_any_permission_codes(env, user, ['permission_b'])


def test_user_has_any_permission_validates_codes_after_a_match(env: Env):
    user = make_user_with_permissions(['permission_a'])
    env.db.add(user)

    with pytest.raises(PermissionConfigurationError, match='Invalid permission code unknown'):
        user_has_any_permission_codes(env, user, ['permission_a', 'unknown'])


def test_user_has_all_permissions(env: Env):
    user = make_user_with_permissions(['permission_a', 'permission_b'])
    env.db.add(user)
    register_permissions(env, ['permission_c'])

    assert user_has_all_permission_codes(env, user, ['permission_a', 'permission_b'])
    assert not user_has_all_permission_codes(env, user, ['permission_a', 'permission_c'])


def test_user_has_all_permissions_validates_codes_after_a_mismatch(env: Env):
    register_permissions(env, ['permission_a'])
    user = make_user_with_permissions([])

    with pytest.raises(PermissionConfigurationError, match='Invalid permission code unknown'):
        user_has_all_permission_codes(env, user, ['permission_a', 'unknown'])


def test_superuser_has_all_permissions(env: Env):
    user = make_user_with_permissions(['superuser'])
    env.db.add(user)
    register_permissions(env, ['permission_a', 'permission_b'])

    assert user_has_all_permission_codes(env, user, ['permission_a', 'permission_b'])


@pytest.mark.parametrize('check', [user_has_any_permission_codes, user_has_all_permission_codes])
def test_permission_collection_cannot_be_empty(
    env: Env,
    check: Callable[[Env, DbUser, Collection[str]], bool],
):
    with pytest.raises(ValueError, match='empty collection'):
        check(env, make_user_with_permissions([]), [])


def test_resolved_permission_checks_do_not_require_a_database(env: Env):
    permission_a = DbPermission(code='permission_a', description='Permission A')
    permission_b = DbPermission(code='permission_b', description='Permission B')
    user = make_user_with_permissions(['permission_a'])

    assert user_has_permission(user, permission_a)
    assert user_has_any_permission(user, [permission_a, permission_b])
    assert not user_has_all_permissions(user, [permission_a, permission_b])


def test_resolved_permission_checks_support_superuser():
    user = make_user_with_permissions(['superuser'])
    permission = DbPermission(code='permission_a', description='Permission A')

    assert user_has_permission(user, permission)

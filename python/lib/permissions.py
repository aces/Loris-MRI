from collections.abc import Collection

from lib.db.models.user import DbUser
from lib.db.queries.permission import get_existing_permission_codes
from lib.env import Env

SUPERUSER_PERMISSION = 'superuser'


class PermissionConfigurationError(Exception):
    """Exception raised when an unregistered permission code is checked."""


def user_has_permission(env: Env, user: DbUser, permission: str) -> bool:
    """
    Check whether a user has a permission.
    """

    _validate_permission_codes(env, [permission])
    return _user_has_registered_permission(user, permission)


def user_has_any_permission(env: Env, user: DbUser, permissions: Collection[str]) -> bool:
    """
    Check whether a user has at least one of a non-empty collection of permissions.
    """

    if not permissions:
        raise ValueError("Cannot check an empty collection of permissions.")

    _validate_permission_codes(env, permissions)
    return any(_user_has_registered_permission(user, permission) for permission in permissions)


def user_has_all_permissions(env: Env, user: DbUser, permissions: Collection[str]) -> bool:
    """
    Check whether a user has every permission in a non-empty collection of permissions.
    """

    if not permissions:
        raise ValueError("Cannot check an empty collection of permissions.")

    _validate_permission_codes(env, permissions)
    return all(_user_has_registered_permission(user, permission) for permission in permissions)


def _user_has_registered_permission(user: DbUser, permission: str) -> bool:
    """
    Check whether a user has a permission assumed to be registered in the database.
    """

    user_permission_codes = {user_permission.code for user_permission in user.permissions}
    return SUPERUSER_PERMISSION in user_permission_codes or permission in user_permission_codes


def _validate_permission_codes(env: Env, pernission_codes: Collection[str]):
    """
    Raise an exception if any permission code in a collection is not registered in the database.
    """

    existing_permissions = get_existing_permission_codes(env.db, pernission_codes)
    invalid_permissions = set(pernission_codes) - existing_permissions
    if invalid_permissions:
        raise PermissionConfigurationError(f"Invalid permission code {sorted(invalid_permissions)[0]}")

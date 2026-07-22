from collections.abc import Collection

from lib.db.models.permission import DbPermission
from lib.db.models.user import DbUser
from lib.db.queries.permission import get_permissions_by_codes
from lib.env import Env

SUPERUSER_PERMISSION = 'superuser'


class PermissionConfigurationError(Exception):
    """Exception raised when an unregistered permission code is checked."""


def user_has_permission(user: DbUser, permission: DbPermission) -> bool:
    """Check whether a user has a resolved permission."""

    user_permission_codes = {user_permission.code for user_permission in user.permissions}
    return SUPERUSER_PERMISSION in user_permission_codes or permission.code in user_permission_codes


def user_has_any_permission(user: DbUser, permissions: Collection[DbPermission]) -> bool:
    """Check for at least one of a non-empty collection of resolved permissions."""

    _require_permissions(permissions)
    return any(user_has_permission(user, permission) for permission in permissions)


def user_has_all_permissions(user: DbUser, permissions: Collection[DbPermission]) -> bool:
    """Check for every permission in a non-empty collection of resolved permissions."""

    _require_permissions(permissions)
    return all(user_has_permission(user, permission) for permission in permissions)


def user_has_permission_code(env: Env, user: DbUser, permission: str) -> bool:
    """Resolve a permission code and check whether a user has that permission."""

    permissions = _resolve_permissions(env, [permission])
    return user_has_permission(user, permissions[0])


def user_has_any_permission_codes(env: Env, user: DbUser, permissions: Collection[str]) -> bool:
    """Resolve permission codes and check whether a user has at least one."""

    _require_permissions(permissions)
    return user_has_any_permission(user, _resolve_permissions(env, permissions))


def user_has_all_permission_codes(env: Env, user: DbUser, permissions: Collection[str]) -> bool:
    """Resolve permission codes and check whether a user has every one."""

    _require_permissions(permissions)
    return user_has_all_permissions(user, _resolve_permissions(env, permissions))


def _resolve_permissions(env: Env, permission_codes: Collection[str]) -> list[DbPermission]:
    """Resolve codes, raising if any permission is not registered."""

    permissions_by_code = {
        permission.code: permission
        for permission in get_permissions_by_codes(env.db, permission_codes)
    }

    invalid_permissions = set(permission_codes) - permissions_by_code.keys()
    if invalid_permissions:
        raise PermissionConfigurationError(f"Invalid permission code {sorted(invalid_permissions)[0]}")

    return [permissions_by_code[code] for code in permission_codes]


def _require_permissions(permissions: Collection[object]):
    if not permissions:
        raise ValueError("Cannot check an empty collection of permissions.")

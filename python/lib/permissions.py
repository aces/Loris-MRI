from collections.abc import Collection, Sequence

from lib.db.models.permission import DbPermission
from lib.db.models.user import DbUser
from lib.db.queries.permission import get_permissions_by_codes
from lib.env import Env

SUPERUSER_PERMISSION = 'superuser'


class PermissionError(Exception):
    """
    Exception raised when an incorrect permission or collection of permissions is checked.
    """


def user_has_permission_code(env: Env, user: DbUser, permission_code: str) -> bool:
    """
    Check whether a user has a permission using that permission code.
    """

    permissions = resolve_permissions(env, [permission_code])
    return user_has_permission(user, permissions[0])


def user_has_any_permission_codes(env: Env, user: DbUser, permission_codes: Collection[str]) -> bool:
    """
    Check whether a user has at least one permission among a non-empty list of permissions using
    these permissions codes.
    """

    permissions = resolve_permissions(env, permission_codes)
    check_non_empty_permissions(permissions)
    return user_has_any_permission(user, permissions)


def user_has_all_permission_codes(env: Env, user: DbUser, permission_codes: Collection[str]) -> bool:
    """
    Check whether a user has all permissions among a non-empty list of permissions using these
    permissions codes.
    """

    permissions = resolve_permissions(env, permission_codes)
    check_non_empty_permissions(permissions)
    return user_has_all_permissions(user, permissions)


def user_has_permission(user: DbUser, permission: DbPermission) -> bool:
    """
    Check whether a user has a permission.
    """

    user_permission_codes = {user_permission.code for user_permission in user.permissions}
    return SUPERUSER_PERMISSION in user_permission_codes or permission.code in user_permission_codes


def user_has_any_permission(user: DbUser, permissions: Collection[DbPermission]) -> bool:
    """
    Check whether a user has at least one permission among a non-empty list of permissions.
    """

    check_non_empty_permissions(permissions)
    return any(user_has_permission(user, permission) for permission in permissions)


def user_has_all_permissions(user: DbUser, permissions: Collection[DbPermission]) -> bool:
    """
    Check whether a user has all permissions among a non-empty list of permissions.
    """

    check_non_empty_permissions(permissions)
    return all(user_has_permission(user, permission) for permission in permissions)


def resolve_permissions(env: Env, permission_codes: Collection[str]) -> Sequence[DbPermission]:
    """
    Resolve permission codes, raising an exception if any permission does not exist in the database.
    """

    # Get the permissions from the permission codes from the database.
    permissions = get_permissions_by_codes(env.db, permission_codes)

    # Map permissions to their permission code.
    permissions_by_code = {permission.code: permission for permission in permissions}

    # Check if any permission code does not have a corresponding database permission.
    invalid_permissions = set(permission_codes) - permissions_by_code.keys()
    if invalid_permissions:
        raise PermissionError(f"Invalid permission codes: {', '.join(sorted(invalid_permissions))}")

    return permissions


def check_non_empty_permissions(permissions: Collection[DbPermission]):
    """
    Raise an exception if a list of permissions is empty.
    """

    if not permissions:
        raise PermissionError("Cannot check an empty collection of permissions.")

from collections.abc import Collection

from lib.db.models.user import DbUser

SUPERUSER_PERMISSION = 'superuser'


def user_has_permission(user: DbUser, permission: str) -> bool:
    """
    Check whether a user has a permission. The superuser permission grants every permission.
    """

    permission_codes = {user_permission.code for user_permission in user.permissions}
    return SUPERUSER_PERMISSION in permission_codes or permission in permission_codes


def user_has_any_permission(user: DbUser, permissions: Collection[str]) -> bool:
    """
    Check whether a user has at least one of a non-empty collection of permissions.
    """

    if not permissions:
        raise ValueError("Cannot check an empty collection of permissions.")

    return any(user_has_permission(user, permission) for permission in permissions)


def user_has_all_permissions(user: DbUser, permissions: Collection[str]) -> bool:
    """
    Check whether a user has every permission in a non-empty collection of permissions.
    """

    if not permissions:
        raise ValueError("Cannot check an empty collection of permissions.")

    return all(user_has_permission(user, permission) for permission in permissions)

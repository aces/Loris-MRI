from lib.db.models.session import DbSession
from lib.db.models.user import DbUser
from lib.env import Env
from lib.modules import is_module_active
from lib.permissions import user_has_any_permission, user_has_permission
from lib.user import can_user_access_project, can_user_access_site

EPHYS_BROWSER_MODULE = 'electrophysiology_browser'
VIEW_ALL_SITES_PERMISSION = 'electrophysiology_browser_view_allsites'
VIEW_OWN_SITES_PERMISSION = 'electrophysiology_browser_view_site'


def can_user_access_ephys_browser(env: Env, user: DbUser) -> bool:
    """
    Check whether a user can access the electrophysiology browser module.
    """

    return is_module_active(env, EPHYS_BROWSER_MODULE) and user_has_any_permission(env, user, [
        VIEW_ALL_SITES_PERMISSION,
        VIEW_OWN_SITES_PERMISSION,
    ])


def can_user_access_ephys_browser_session(env: Env, user: DbUser, session: DbSession) -> bool:
    """
    Check whether a user can view an electrophysiology browser session.
    """

    if not can_user_access_ephys_browser(env, user) or not can_user_access_project(env, user, session.project):
        return False

    if user_has_permission(env, user, VIEW_ALL_SITES_PERMISSION):
        return True

    if user_has_permission(env, user, VIEW_OWN_SITES_PERMISSION) and can_user_access_site(env, user, session.site):
        return True

    return False

from lib.db.models.session import DbSession
from lib.db.models.user import DbUser
from lib.env import Env
from lib.modules import module_is_active
from lib.permissions import user_has_any_permission_codes, user_has_permission_code
from lib.user import user_can_access_project, user_can_access_site

EPHYS_BROWSER_MODULE = 'electrophysiology_browser'
VIEW_ALL_SITES_PERMISSION = 'electrophysiology_browser_view_allsites'
VIEW_OWN_SITES_PERMISSION = 'electrophysiology_browser_view_site'


def user_can_access_ephys_browser(env: Env, user: DbUser) -> bool:
    """
    Check whether a user can access the electrophysiology browser module.
    """

    return module_is_active(env, EPHYS_BROWSER_MODULE) and user_has_any_permission_codes(env, user, [
        VIEW_ALL_SITES_PERMISSION,
        VIEW_OWN_SITES_PERMISSION,
    ])


def user_can_access_ephys_browser_session(env: Env, user: DbUser, session: DbSession) -> bool:
    """
    Check whether a user can view an electrophysiology browser session.
    """

    if not user_can_access_ephys_browser(env, user) or not user_can_access_project(env, user, session.project):
        return False

    if user_has_permission_code(env, user, VIEW_ALL_SITES_PERMISSION):
        return True

    if user_has_permission_code(env, user, VIEW_OWN_SITES_PERMISSION) and user_can_access_site(env, user, session.site):
        return True

    return False

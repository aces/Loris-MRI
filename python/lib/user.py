from datetime import timedelta

from lib.db.misc import get_database_time
from lib.db.models.project import DbProject
from lib.db.models.site import DbSite
from lib.db.models.user import DbUser
from lib.db.queries.user_login_history import count_failed_logins_since, try_get_last_successful_login_time
from lib.env import Env


def is_user_account_locked(env: Env, username: str, ip_address: str) -> bool:
    """
    Check whether a user has made too many failed login attempts from a client IP.
    """

    database_time = get_database_time(env.db)
    last_successful_login_time = try_get_last_successful_login_time(env.db, username)

    for window, threshold in ((timedelta(minutes=15), 10), (timedelta(minutes=60), 15)):
        start_time = database_time - window
        if last_successful_login_time is not None:
            start_time = max(start_time, last_successful_login_time)

        if count_failed_logins_since(env.db, username, ip_address, start_time) > threshold:
            return True

    return False


def can_user_access_project(_: Env, user: DbUser, project: DbProject) -> bool:
    """
    Check whether a user has access to a project.
    """

    return project in user.projects


def can_user_access_site(_: Env, user: DbUser, site: DbSite) -> bool:
    """
    Check whether a user has access to a site.
    """

    return site in user.sites

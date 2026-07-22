from datetime import timedelta

from lib.config import get_user_maximum_days_inactive_config
from lib.db.misc import get_database_time
from lib.db.models.project import DbProject
from lib.db.models.site import DbSite
from lib.db.models.user import DbUser
from lib.db.queries.user_login_history import count_failed_logins_since, try_get_last_successful_login_time
from lib.env import Env


def check_user_account_active(env: Env, user: DbUser) -> bool:
    """
    Check whether a user account is active. This function can mark the user as inactive if the
    maximum inactive days configuration is enabled and the user exceeds this limit.
    """

    if not user.active or user.pending_approval or user.password_change_required:
        return False

    database_time = get_database_time(env.db)
    maximum_days_inactive = get_user_maximum_days_inactive_config(env)

    # If the maximum inactive days configuration is enabled, check last login time and mark the user
    # as inactive if the limit is exceeded.
    if maximum_days_inactive is not None:
        last_login_time = try_get_last_successful_login_time(env.db, user.username)
        if last_login_time is not None and (database_time - last_login_time).days > maximum_days_inactive:
            user.active = False
            env.db.commit()
            return False

    current_date = database_time.date()
    if user.active_from is not None and current_date < user.active_from:
        return False

    if user.active_to is not None and current_date > user.active_to:
        return False

    return True


def check_user_account_locked(env: Env, username: str, ip_address: str) -> bool:
    """
    Check whether a user has made too many failed login attempts from a client IP.
    """

    database_time = get_database_time(env.db)
    last_successful_login_time = try_get_last_successful_login_time(env.db, username)

    # Check the number of failed login attempts in the specified time windows (10 attempts within 15
    # minutes or 15 attempts within 60 minutes).
    for window, threshold in [(timedelta(minutes=15), 10), (timedelta(minutes=60), 15)]:
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

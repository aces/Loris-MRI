from lib.db.models.project import DbProject
from lib.db.models.session import DbSession
from lib.db.models.site import DbSite
from lib.db.models.user import DbUser
from lib.env import Env


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


def can_user_access_session(env: Env, user: DbUser, session: DbSession) -> bool:
    """
    Check whether a user has access to a session.
    """

    return can_user_access_site(env, user, session.site) and can_user_access_project(env, user, session.project)

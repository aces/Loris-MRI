import pytest

from lib.db.models.module import DbModule
from lib.db.models.permission import DbPermission
from lib.db.models.project import DbProject
from lib.db.models.session import DbSession
from lib.db.models.site import DbSite
from lib.db.models.user import DbUser
from lib.env import Env
from lib.physio.permissions import (
    EPHYS_BROWSER_MODULE,
    VIEW_ALL_SITES_PERMISSION,
    VIEW_OWN_SITES_PERMISSION,
    can_user_access_ephys_browser,
    can_user_access_ephys_browser_session,
)


@pytest.mark.parametrize(
    ('permission', 'same_project', 'same_site', 'module_active', 'expected'),
    [
        (None, True, True, True, False),
        ('superuser', True, False, True, True),
        (VIEW_OWN_SITES_PERMISSION, True, True, True, True),
        (VIEW_OWN_SITES_PERMISSION, True, False, True, False),
        (VIEW_ALL_SITES_PERMISSION, True, False, True, True),
        (VIEW_ALL_SITES_PERMISSION, False, True, True, False),
        (VIEW_ALL_SITES_PERMISSION, True, True, False, False),
    ],
)
def test_ephys_browser_session_access(
    env: Env,
    permission: str | None,
    same_project: bool,
    same_site: bool,
    module_active: bool,
    expected: bool,
):
    module = DbModule(name=EPHYS_BROWSER_MODULE, active=module_active)

    view_all = DbPermission(code=VIEW_ALL_SITES_PERMISSION, description='View all sites', module=module)
    view_own = DbPermission(code=VIEW_OWN_SITES_PERMISSION, description='View own sites', module=module)

    project = DbProject(id=1, name='Project', alias='P')
    other_project = DbProject(id=2, name='Other project', alias='O')

    site = DbSite(id=1, name='Site', alias='S', mri_alias='S')
    other_site = DbSite(id=2, name='Other site', alias='O', mri_alias='O')

    permissions = {
        VIEW_ALL_SITES_PERMISSION: view_all,
        VIEW_OWN_SITES_PERMISSION: view_own,
        'superuser': DbPermission(code='superuser', description='Superuser'),
    }

    user = DbUser(
        username='test_user',
        email='test@example.com',
        projects=[project] if same_project else [other_project],
        sites=[site] if same_site else [other_site],
        permissions=[] if permission is None else [permissions[permission]],
    )

    session = DbSession(candidate_id=1, visit_label='V1', project=project, site=site)

    env.db.add_all([module, view_all, view_own, user])

    assert can_user_access_ephys_browser_session(env, user, session) is expected


def test_ephys_browser_access_requires_a_view_permission(env: Env):
    env.db.add_all([
        DbModule(name=EPHYS_BROWSER_MODULE, active=True),
        DbPermission(code=VIEW_ALL_SITES_PERMISSION, description='View all sites'),
        DbPermission(code=VIEW_OWN_SITES_PERMISSION, description='View own sites'),
    ])

    user = DbUser(username='test_user', email='test@example.com')

    assert not can_user_access_ephys_browser(env, user)

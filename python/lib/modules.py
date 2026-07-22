from lib.db.queries.module import try_get_module_with_name
from lib.env import Env


def is_module_active(env: Env, module_name: str) -> bool:
    """
    Check whether a LORIS module is registered and active.
    """

    module = try_get_module_with_name(env.db, module_name)
    return module is not None and module.active

import os
from typing import Any

from lib.db.connect import connect_to_db
from lib.db.query.config import get_config_with_setting_name
from lib.dataclass.env import Env
from lib.log import write_to_log_file
from lib.lorisgetopt import LorisGetOpt


def make_env(loris_get_opt: LorisGetOpt):
    """
    Create a new script environment using the provided LORIS options object.
    """

    db = connect_to_db(loris_get_opt.config_info.mysql)  # type: ignore
    data_dir = str(get_config_with_setting_name(db, 'dataDirBasepath').value)
    tmp_dir = os.path.basename(loris_get_opt.tmp_dir)
    script_name = loris_get_opt.script_name
    verbose = loris_get_opt.options_dict['verbose']['value']  # type: ignore
    log_dir = os.path.join(data_dir, 'logs', script_name)
    if not os.path.isdir(log_dir):
        os.makedirs(log_dir)
    log_file = os.path.join(log_dir, f'{tmp_dir}.log')
    env = Env(
        db,
        loris_get_opt.script_name,
        log_file,
        verbose,  # type: ignore
        [],
    )

    log_file_header = get_log_file_header(env, loris_get_opt.options_dict)
    write_to_log_file(env, log_file_header)
    return env


def get_log_file_header(env: Env, script_options: dict[str, Any]):
    run_info = os.path.basename(env.log_file[:-13])
    title = run_info.replace('_', ' ').upper()
    message = (
        "\n"
        "----------------------------------------------------------------\n"
        f"  {title}\n"
        "----------------------------------------------------------------\n"
        "\n"
        "Script run with the following options set\n"
    )

    for key in script_options:
        if script_options[key]['value']:
            message += f"  --{key}: {script_options[key]['value']}\n"

    message += "\n"
    return message

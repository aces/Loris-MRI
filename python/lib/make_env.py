import os
from typing import Any, cast

from sqlalchemy.orm import Session

from lib.config_file import DatabaseConfig
from lib.db.connect import get_database_engine
from lib.db.query.config import get_config_with_setting_name
from lib.env import Env
from lib.logging import log_verbose, write_to_log_file
from lib.lorisgetopt import LorisGetOpt


def make_env(loris_get_opt: LorisGetOpt):
    """
    Create a new script environment using the provided LORIS options object.
    """

    verbose = cast(bool, loris_get_opt.options_dict['verbose']['value'])
    config = cast(DatabaseConfig, loris_get_opt.config_info.mysql)  # type: ignore
    script_name = loris_get_opt.script_name

    # Connect to the database

    if verbose:
        print(
            'Connecting to the database using the following configuration:\n'
            f'  Host: {config.host}\n'
            f'  Port: {config.port}\n'
            f'  Database: {config.database}\n'
            f'  Username: {config.username}\n'
            '  (password hidden)'
        )

    engine = get_database_engine(config)
    db = Session(engine)

    # Create the log file

    data_dir = str(get_config_with_setting_name(db, 'dataDirBasepath').value)
    tmp_dir = os.path.basename(loris_get_opt.tmp_dir)
    log_dir = os.path.join(data_dir, 'logs', script_name)
    if not os.path.isdir(log_dir):
        os.makedirs(log_dir)

    log_file = os.path.join(log_dir, f'{tmp_dir}.log')

    env = Env(
        engine,
        db,
        script_name,
        log_file,
        verbose,
        [],
    )

    log_file_header = get_log_file_header(env, loris_get_opt.options_dict)
    write_to_log_file(env, log_file_header)

    log_verbose(env, 'Successfully connected to the database')

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

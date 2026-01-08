import os
import sys
from typing import Any, cast

from sqlalchemy.orm import Session

import lib.exitcode
from lib.config_file import DatabaseConfig
from lib.db.connect import get_database_engine
from lib.db.queries.config import try_get_config_with_setting_name
from lib.env import Env
from lib.logging import log_verbose, write_to_log_file
from lib.lorisgetopt import LorisGetOpt


def make_env_from_opts(loris_get_opt: LorisGetOpt) -> Env:
    """
    Create a new script environment using the provided LORIS options object.
    """

    script_name = loris_get_opt.script_name
    script_options = loris_get_opt.options_dict
    config_info = loris_get_opt.config_info
    tmp_dir = loris_get_opt.tmp_dir
    verbose = loris_get_opt.options_dict['verbose']['value']   # type: ignore
    return make_env(script_name, script_options, config_info, tmp_dir, verbose)  # type: ignore


def make_env(
    script_name: str,
    script_options: dict[str, Any],
    config_info: Any,
    tmp_dir_path: str,
    verbose: bool,
) -> Env:
    """
    Create a new script environment using the provided arguments.
    """

    # Connect to the database
    db_config = cast(DatabaseConfig, config_info.mysql)

    if verbose:
        print(
            'Connecting to the database using the following configuration:\n'
            f'  Host: {db_config.host}\n'
            f'  Port: {db_config.port}\n'
            f'  Database: {db_config.database}\n'
            f'  Username: {db_config.username}\n'
            '  (password hidden)'
        )

    engine = get_database_engine(db_config)
    db = Session(engine)

    # Create the log file

    data_dir_config = try_get_config_with_setting_name(db, 'dataDirBasepath')
    if data_dir_config is None or data_dir_config.value is None:
        print("Missing 'dataDirBasepath' configuration in the database.", file=sys.stderr)
        sys.exit(lib.exitcode.BAD_CONFIG_SETTING)

    data_dir = data_dir_config.value
    log_dir = os.path.join(data_dir, 'logs', script_name)
    if not os.path.isdir(log_dir):
        os.makedirs(log_dir)

    log_file = os.path.join(log_dir, f'{os.path.basename(tmp_dir_path)}.log')

    env = Env(
        engine,
        db,
        script_name,
        config_info,
        log_file,
        verbose,
        [],
    )

    log_file_header = get_log_file_header(env, script_options)
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

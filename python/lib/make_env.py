import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any, cast

from sqlalchemy.orm import Session

import lib.exitcode
from lib.config_file import DatabaseConfig
from lib.db.connect import get_database_engine
from lib.db.queries.config import try_get_config_with_setting_name
from lib.env import Env
from lib.logging import log_verbose, write_to_log_file


def make_env(
    script_name: str,
    script_options: dict[str, Any],
    config_info: Any,
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

    data_dir = Path(data_dir_config.value)

    tmp_dir_path = create_script_tmp_dir(script_name)

    log_dir_path = data_dir / 'logs' / script_name
    log_dir_path.mkdir(exist_ok=True)

    log_file_path = log_dir_path / f'{tmp_dir_path.name}.log'

    env = Env(
        engine,
        db,
        script_name,
        config_info,
        tmp_dir_path,
        log_file_path,
        verbose,
        [],
    )

    log_file_header = get_log_file_header(env, script_options)
    write_to_log_file(env, log_file_header)

    log_verbose(env, 'Successfully connected to the database')

    return env


def get_log_file_header(env: Env, script_options: dict[str, Any]):
    run_info = env.log_file_path.name[:-13]
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


def create_script_tmp_dir(script_name: str) -> Path:
    """
    Create a recognizable temporary directory for the current pipeline.
    """

    # Get the temporary directory from the OS, notably from the `TMPDIR` environment variable.
    env_tmp_dir = tempfile.gettempdir()

    # Create a recognizable temporary directory name for this pipeline.
    date_string = datetime.now().strftime('%Y-%m-%d_%Hh%Mm%Ss_')
    tmp_dir_prefix = f'{script_name}_{date_string}'

    # Create and return the pipeline temporary directory.
    return Path(tempfile.mkdtemp(prefix=tmp_dir_prefix, dir=env_tmp_dir))

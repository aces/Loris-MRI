import sys
from datetime import datetime
from typing import Never

from lib.db.models.notification_spool import DbNotificationSpool
from lib.env import Env


def log(env: Env, message: str):
    """
    Log a standard message.
    """

    print(message)
    write_to_log_file(env, message)
    register_notification(env, message, False, False)


def log_verbose(env: Env, message: str):
    """
    Log a verbose message, which is displayed only if the script is running in verbose mode.
    """

    if env.verbose:
        print(message)

    write_to_log_file(env, message)
    register_notification(env, message, False, True)


def log_warning(env: Env, message: str):
    """
    Log a warning message.
    """

    full_message = f"WARNING: {message}"
    print(full_message, file=sys.stderr)
    write_to_log_file(env, full_message)
    register_notification(env, full_message, True, False)


def log_error(env: Env, message: str):
    """
    Log an error message without exiting the program.
    """

    full_message = f"ERROR: {message}"
    print(full_message, file=sys.stderr)
    write_to_log_file(env, full_message)
    register_notification(env, full_message, True, False)


def log_error_exit(env: Env, message: str, exit_code: int = -1) -> Never:
    """
    Log an error message and exit the program, executing the cleanup procedures while doing so.
    """

    log_error(env, message)
    env.run_cleanups()
    sys.exit(exit_code)


def write_to_log_file(env: Env, message: str):
    """
    Write a message to the log file of the environment.
    """

    with open(env.log_file, 'a') as file:
        file.write(f"{message}\n")


def register_notification(env: Env, message: str, is_error: bool, is_verbose: bool):
    """
    Log a message in the database notifications if the notification information of the environment
    have been initialized.
    """

    if env.notifier is None:
        return

    notification = DbNotificationSpool(
        type_id      = env.notifier.type_id,
        time_spooled = datetime.now(),
        message      = message,
        origin       = env.notifier.origin,
        process_id   = env.notifier.process_id,
        error        = is_error,
        verbose      = is_verbose,
        sent         = False,
        active       = True,
    )

    env.notifier.db.add(notification)
    env.notifier.db.commit()

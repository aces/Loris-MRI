from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from sqlalchemy import Engine
from sqlalchemy.orm import Session

from lib.db.models.notification_type import DbNotificationType
from lib.db.queries.notification import try_get_notification_type_with_name


@dataclass
class Notifier:
    """
    This class wraps information used to send the script logs to the database.
    """

    # Database session of the notifier, separate from the main database session to not hinder its
    # transactions
    db: Session
    # Notification type ID
    type_id: int
    # Notification origin, which is usually the script name
    origin: str
    # Process ID, which is usually the MRI upload ID
    process_id: int


@dataclass
class Env:
    """
    This class wraps information about the environmentin which a LORIS-MRI script is executed. It
    notably stores the database handle and various information used for logging.
    """

    db_engine: Engine
    db: Session
    script_name: str
    config_info: Any
    log_file: str
    verbose: bool
    cleanups: list[Callable[[], None]]
    notifier: Notifier | None = None

    def add_cleanup(self, cleanup: Callable[[], None]):
        """
        Add a cleanup function to the environment, which will be executed if the program exits
        early.
        """

        self.cleanups.append(cleanup)

    def run_cleanups(self):
        """
        Run all the cleanup functions of the environment in the reverse insertion order (most
        recent is ran first). This clears the cleanup functions list.
        """

        while self.cleanups != []:
            cleanup = self.cleanups.pop()
            cleanup()

    def init_notifier(self, process_id: int):
        """
        Associate the current script with a given process ID, which notably allows to start logging
        execution information in the database.
        """

        notification_db = Session(self.db_engine)
        notification_type_name = f'PYTHON {self.script_name.replace("_", " ").upper()}'
        notification_type = try_get_notification_type_with_name(notification_db, notification_type_name)
        if notification_type is None:
            notification_type = DbNotificationType(
                name    = notification_type_name,
                private = False,
            )

            notification_db.add(notification_type)
            notification_db.commit()

        self.notifier = Notifier(
            notification_db,
            notification_type.id,
            f'{self.script_name}.py',
            process_id,
        )

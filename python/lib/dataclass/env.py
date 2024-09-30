from dataclasses import dataclass
from typing import Callable
from sqlalchemy.orm import Session as Database

from lib.db.query.notification import get_notification_type_with_name


@dataclass
class NotifInfo:
    """
    This class wraps information used to send the script logs to the database.
    """

    # Noification type ID
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

    db: Database
    script_name: str
    log_file: str
    verbose: bool
    cleanups: list[Callable[[], None]]
    notif_info: NotifInfo | None = None

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

    def set_process_id(self, process_id: int):
        """
        Associate the current script with a given process ID, which notably allows to start logging
        execution information in the database.
        """

        notification_type_name = f'PYTHON {self.script_name.replace("_", " ").upper()}'
        notification_type = get_notification_type_with_name(self.db, notification_type_name)
        self.notif_info = NotifInfo(
            notification_type.id,
            f'{self.script_name}.py',
            process_id,
        )

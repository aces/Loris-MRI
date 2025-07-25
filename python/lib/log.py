""""""

import os

from typing_extensions import deprecated

from lib.database_lib.notification import Notification


@deprecated('Use `lib.logging` instead')
class Log:
    """
    Class that handles the log edition of the imaging pipeline.
    """

    def __init__(self, db, data_dir, script_name, log_file_basename, script_options, verbose):
        """
        Initialize the Log class and creates the log file in which all messages created
        by the script being run will be stored.

        :param db: database class object
         :type db: object
        :param data_dir: path to the imaging data_dir
         :type data_dir: str
        :param script_name: name of the script creating this log
         :type script_name: str
        :param log_file_basename: the basename to use for the log file name
         :type log_file_basename: str
        :param script_options: dictionary with all the script options to be logged
         :type script_options: dict
        :param verbose: whether to be verbose
         :type verbose: bool
        """
        self.db = db
        self.verbose = verbose

        self.script_name = script_name
        self.script_options = script_options
        self.log_dir = os.path.join(data_dir, "logs", script_name)
        if not os.path.isdir(self.log_dir):
            os.makedirs(self.log_dir)
        self.log_file = os.path.join(self.log_dir, f"{log_file_basename}.log")

        # set notification_db_obj to None until we get a confirmed UploadID to insert proper notification into the
        # database related to the UploadID
        self.notification_db_obj = None

        self.create_log_header()

    @deprecated('Use `lib.env.Env.init_notifier` instead')
    def initiate_notification_db_obj(self, upload_id):
        """
        Instantiate the notification_db_obj to be able to write in the notification table. This can only be done
        once we know the upload_id, hence the separate function to initiate the database object.

        :param upload_id: UploadID that will be used as the ProcessID for the notification table
         :type upload_id: int
        """
        self.notification_db_obj = Notification(
            self.db,
            self.verbose,
            notification_type=f"PYTHON {self.script_name.replace('_', ' ').upper()}",
            notification_origin=f"{self.script_name}.py",
            process_id=upload_id
        )

    def write_to_notification_table(self, message, is_error, is_verbose):
        """
        Writes a message into the notification table.

        :param message: message to be logged in the notification table
         :type message: str
        :param is_error: 'Y' or 'N' to be inserted into the notification table column 'Error'
         :type is_error: str
        :param is_verbose: 'Y' or 'N' to be inserted into the notification table column 'Verbose'
         :type is_verbose: str
        """
        # if notification_db_obj initiated, write message to notification table
        if self.notification_db_obj:
            self.notification_db_obj.write_to_notification_spool(message, is_error, is_verbose)

    def write_to_log_file(self, message):
        """
        Function that writes a message at the end of the log file.

        :param message: the message to be written in the log file
         :type message: str
        """

        f = open(self.log_file, "a")
        f.write(message)
        f.close()

    def create_log_header(self):
        """
        Function that creates the header of the log file with the script name information
        as well as the options that were provided to the script.
        """

        run_info = os.path.basename(self.log_file[:-13])
        message = f"""
----------------------------------------------------------------
  {run_info.replace("_", " ").upper()}
----------------------------------------------------------------

Script run with the following options set
"""
        for key in self.script_options:
            if self.script_options[key]["value"]:
                message += f"  --{key}: {self.script_options[key]['value']}\n"

        self.write_to_log_file(f"{message}\n\n")

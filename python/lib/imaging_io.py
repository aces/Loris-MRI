import datetime
import os
import shutil
import sys
import tarfile
import tempfile

from lib.exitcode import COPY_FAILURE

"""Set of io functions."""

__license__ = "GPLv3"


class ImagingIO:
    def __init__(self, log_obj, verbose):
        self.log_obj = log_obj
        self.verbose = verbose

    def extract_archive(self, location, prefix, tmp_dir):
        """
        Extract Archive in the temporary directory

        :return: extracted directory path
            :rtype: str
        """

        now = datetime.datetime.now()
        upload_prefix = f'{prefix}_DIR_{now.strftime("%Y-%m-%d_%Hh%Mm%Ss")}_'
        extract_location = tempfile.mkdtemp(prefix=upload_prefix, dir=tmp_dir)
        tar_file = tarfile.open(location)
        tar_file.extractall(extract_location)
        tar_file.close()
        return extract_location

    def remove_dir(self, dir):
        """
        Removes a directory and its content
        """

        if os.path.exists(dir):
            try:
                shutil.rmtree(dir)
            except PermissionError as err:
                self.log_info(f"Could not delete {dir}. Error was: {err}", is_error=True, is_verbose=False)

    def copy_file(self, old_file_path, new_file_path):
        """
        Move a file on the file system.

        :param old_file_path: where to move the file from
        :type old_file_path: str
        :param new_file_path: where to move the file to
        :type new_file_path: str
        """

        self.log_info(f'Moving {old_file_path} to {new_file_path}')
        shutil.copytree(old_file_path, new_file_path, dirs_exist_ok=True)
        if not os.path.exists(new_file_path):
            message = f'Could not copy {old_file_path} to {new_file_path}'
            self.log_error_and_exit(message, COPY_FAILURE, is_error=True)

    def log_info(self, message, is_error=False, is_verbose=True, to_file=True, to_table=True):
        """
        Function to log information that need to be logged in the notification_spool table and in the log
        file produced by the script executed.

        :param message: message to log
            :type message: str
        :param to_file: log message to a file
            :type to_file: bool
        :param to_table: log message to a table
            :type to_table: bool
        :param is_error: whether the message to log is an error or not
            :type is_error: bool
        :param to_file: whether to log to a file
         :type to_file: bool
        :param to_table: whether to log to the notification table
         :type to_table: bool
        """
        log_msg = f"==> {message}"

        is_error_str = 'Y' if is_error else 'N'
        is_verbose_str = 'Y' if is_verbose else 'N'

        if to_file:
            self.log_obj.write_to_log_file(f"{log_msg}\n")
        if to_table:
            self.log_obj.write_to_notification_table(log_msg, is_error_str, is_verbose_str)

        if self.verbose:
            print(f"{log_msg}\n")

    def log_error_and_exit(self, message, exit_code, callback = None):
        """
        Function to commonly executes all logging information when the script needs to be
        interrupted due to an error. It will log the error in the log file created by the
        script being executed, add an entry with the error in the notification_spool table
        and print the error to the user in the terminal.

        :param message: message to log before exit
            :type message: str
        :param exit_code: exit code to use to exit the script
            :type exit_code: int
        :param callback: function to execute before exiting
            :type callback: function
        """

        err_msg = f"[ERROR   ] {message}"
        self.log_obj.write_to_log_file(f"{err_msg}\n")
        self.log_obj.write_to_notification_table(err_msg, 'Y', 'N')
        print(f"\n{err_msg}\n")
        if callback:
            callback()
        sys.exit(exit_code)

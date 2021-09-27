""""""

import os

__license__ = "GPLv3"


class Log:
    """
    Class that handles the log edition of the imaging pipeline.
    """

    def __init__(self, data_dir, script_name, log_file_basename, script_options):
        """
        Initialize the Log class and creates the log file in which all messages created
        by the script being run will be stored.

        :param data_dir: path to the imaging data_dir
         :type data_dir: str
        :param script_name: name of the script creating this log
         :type script_name: str
        :param log_file_basename: the basename to use for the log file name
         :type log_file_basename: str
        :param script_options: dictionary with all the script options to be logged
         :type script_options: dict
        """
        self.script_name = script_name
        self.script_options = script_options
        self.log_dir = os.path.join(data_dir, "logs", script_name)
        if not os.path.isdir(self.log_dir):
            os.makedirs(self.log_dir)
        self.log_file = os.path.join(self.log_dir, f"{log_file_basename}.log")
        self.create_log_header()

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

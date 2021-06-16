""""""

import os

__license__ = "GPLv3"


class Log:
    """

    """

    def __init__(self, data_dir, script_name, log_file_basename, script_options):
        self.script_name = script_name
        self.script_options = script_options
        self.log_dir = os.path.join(data_dir, "logs", script_name)
        if not os.path.isdir(self.log_dir):
            os.makedirs(self.log_dir)
        self.log_file = os.path.join(self.log_dir, f"{log_file_basename}.log")
        print(self.log_file)
        self.create_log_header()


    def write_to_log_file(self, message):

        f = open(self.log_file, "a")
        f.write(message)
        f.close()

    def create_log_header(self):

        run_info = os.path.basename(self.log_file[:-13])
        message = f"""
----------------------------------------------------------------
  {run_info.replace("_", " ").upper()}
----------------------------------------------------------------
Script run with the following options set       
"""
        for key in self.script_options:
            if self.script_options[key]["value"]:
                message += f"\t- --{key}: {self.script_options[key]['value']}\n"

        self.write_to_log_file(f"{message}\n\n")
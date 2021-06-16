""""""

import lib.exitcode
import os
import sys

__license__ = "GPLv3"

class LorisGetOpt:
    """

    """

    def __init__(self, usage, options_dict):
        self.usage = usage
        self.options_dict = options_dict
        self.long_options = self.get_long_options()
        self.short_options = self.get_short_options()
        self.config_info = None

    def get_long_options(self):
        long_options = []
        for key in self.options_dict:
            option = f"{key}=" if self.options_dict[key]["expect_arg"] else key
            long_options.append(option)

        return long_options

    def get_short_options(self):
        short_options = []
        for key in self.options_dict:
            short_opt = self.options_dict[key]["short_opt"]
            option = f"{short_opt}:" if self.options_dict[key]["expect_arg"] else short_opt
            short_options.append(option)

        return short_options

    def populate_options_dict_values(self, opts):

        for opt, arg in opts:
            if opt in ("-h", "--help"):
                print(self.usage)
                sys.exit()
            else:
                for key in self.options_dict:
                    long_opt = f"--{key}"
                    short_opt = f"-{self.options_dict[key]['short_opt']}"
                    if opt in (long_opt, short_opt):
                        if not self.options_dict[key]["expect_arg"]:
                            arg = True
                        self.options_dict[key]["value"] = arg

    def perform_default_checks_and_load_config(self):

        # perform some initial checks
        self.check_required_options_are_set()
        self.check_options_file_path_exists()
        self.load_config_file()

    def load_config_file(self):

        profile_value = self.options_dict["profile"]["value"]

        if "LORIS_CONFIG" not in os.environ.keys():
            print("[ERROR   ] Environment variable 'LORIS_CONFIG' not set\n")
            sys.exit(lib.exitcode.INVALID_ENVIRONMENT_VAR)

        config_file = os.path.join(os.environ["LORIS_CONFIG"], ".loris_mri", profile_value)
        if not config_file.endswith(".py"):
            print(
                f"[ERROR   ] {config_file} does not appear to be the python configuration file."
                f" Try using 'database_config.py' instead.\n"
            )
            sys.exit(lib.exitcode.INVALID_ARG)

        if os.path.isfile(config_file):
            sys.path.append(os.path.dirname(config_file))
            self.config_info = __import__(os.path.basename(config_file[:-3]))
        else:
            print(f"[ERROR   ] {profile_value} does not exist in {os.environ['LORIS_CONFIG']}.")
            sys.exit(lib.exitcode.INVALID_PATH)

    def check_required_options_are_set(self):

        for key in self.options_dict:
            opt_value = self.options_dict[key]["value"]
            if self.options_dict[key]['required'] and not opt_value:
                print(f"[ERROR   ] argument --{key} is required\n")
                print(self.usage)
                sys.exit(lib.exitcode.MISSING_ARG)

    def check_options_file_path_exists(self):

        for key in self.options_dict:
            opt_value = self.options_dict[key]["value"]
            if self.options_dict[key]["is_path"] and opt_value and not os.path.isfile(opt_value):
                print(f"[ERROR   ] {opt_value} does not exist. Please provide a valid path for --{key}\n")
                print(self.usage)
                sys.exit(lib.exitcode.INVALID_PATH)
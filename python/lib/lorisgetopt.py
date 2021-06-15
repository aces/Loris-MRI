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
                        print(opt)
                        print(arg)
                        if not self.options_dict[key]["expect_arg"]:
                            arg = True
                        if key == "profile":
                             arg = os.path.join(os.environ['LORIS_CONFIG'], ".loris_mri", arg)
                        self.options_dict[key]["value"] = arg

        # perform some initial checks
        self.check_required_options_are_set()
        self.check_options_file_path_exists()


    def check_required_options_are_set(self):

        for key in self.options_dict:
            opt_value = self.options_dict[key]["value"]
            if self.options_dict[key]['required'] and not opt_value:
                print(f"ERROR: argument --{key} is required\n")
                print(self.usage)
                sys.exit(lib.exitcode.MISSING_ARG)

    def check_options_file_path_exists(self):

        for key in self.options_dict:
            opt_value = self.options_dict[key]["value"]
            if self.options_dict[key]["is_path"] and opt_value and not os.path.isfile(opt_value):
                print(f"ERROR: {opt_value} does not exist. Please provide a valid path for --{key}")
                print(self.usage)
                sys.exit(lib.exitcode.INVALID_PATH)
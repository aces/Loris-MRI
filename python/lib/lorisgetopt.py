""""""
import getopt

import lib.exitcode
import os
import sys

__license__ = "GPLv3"


class LorisGetOpt:
    """
    This class will handle GetOpt functions for scripts to be run.

    When writing a new script, the developer will need to provide a usage text and a dictionary
    that will hold the properties of the different options the script will handle.

    Example for a script with options --profile --file_path and --verbose

    from lib.lorisgetopt import LorisGetOpt
    usage = (
        "\n"

        "********************************************************************\n"
        " EXAMPLE SCRIPT\n"
        "********************************************************************\n"
        "The program is an example. More description would go here\n\n"

        "usage  : example.py -p <profile> -f <file_path> ...\n\n"

        "options: \n"
        "\t-p, --profile   : Name of the python database config file in dicom-archive/.loris_mri\n"
        "\t-n, --file_path : Absolute file path to process\n"
        "\t-v, --verbose   : If set, be verbose\n\n"

        "required options are: \n"
        "\t--profile\n"
        "\t--file_path\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "file_path": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "f", "is_path": True
        },
        "verbose": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "v", "is_path": False
        },
        "help": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "h", "is_path": False
        },
    }

    # get the options provided by the user
    loris_getopt_obj = LorisGetOpt(usage, options_dict)

    # validate that the options provided are correct
    loris_getopt_obj.perform_default_checks_and_load_config()

    """

    def __init__(self, usage, options_dict):
        """
        Initialize the class, run GetOpt and populate the options_dict with the values that
        were provided to the script.
        """
        self.usage = usage
        self.options_dict = options_dict
        self.long_options = self.get_long_options()
        self.short_options = self.get_short_options()
        self.config_info = None

        try:
            opts, args = getopt.getopt(sys.argv[1:], "".join(self.short_options), self.long_options)
        except getopt.GetoptError as err:
            print(err)
            print(self.usage)
            sys.exit(lib.exitcode.GETOPT_FAILURE)

        self.populate_options_dict_values(opts)

    def get_long_options(self):
        """
        Determines what the long options should be for the getopt table.

        :return: list of all the long options for getopt
         :rtype: list
        """
        long_options = []
        for key in self.options_dict:
            option = f"{key}=" if self.options_dict[key]["expect_arg"] else key
            long_options.append(option)

        return long_options

    def get_short_options(self):
        """
        Determines what the short options should be for the getopt table.

        :return: concatenated string with all the short options for getopt
         :rtype: str
        """
        short_options = []
        for key in self.options_dict:
            short_opt = self.options_dict[key]["short_opt"]
            option = f"{short_opt}:" if self.options_dict[key]["expect_arg"] else short_opt
            short_options.append(option)

        return short_options

    def populate_options_dict_values(self, opts):
        """
        Populates the options dictionary with the values provided to the script so that they
        can be used later on during processing.
        """

        for opt, arg in opts:
            if opt in ("-h", "--help"):
                print(self.usage)
                sys.exit()
            else:
                self.check_option_is_in_the_list_of_possible_options(opt)
                for key in self.options_dict:
                    long_opt = f"--{key}"
                    short_opt = f"-{self.options_dict[key]['short_opt']}"
                    if opt in (long_opt, short_opt):
                        if not self.options_dict[key]["expect_arg"]:
                            arg = True
                        self.options_dict[key]["value"] = arg

    def perform_default_checks_and_load_config(self):
        """
        Regroups all the different default checks that should be run on GetOpt information
        provided when running the script.
        """

        # perform some initial checks
        self.check_required_options_are_set()
        self.check_options_file_path_exists()
        self.load_config_file()

    def load_config_file(self):
        """
        Loads the config file based on the value provided by the option '--profile' when
        running the script. If the config file cannot be loaded, the script will exit
        with a proper error message.
        """

        profile_value = self.options_dict["profile"]["value"]

        if "LORIS_CONFIG" not in os.environ.keys():
            print("\n[ERROR   ] Environment variable 'LORIS_CONFIG' not set\n")
            sys.exit(lib.exitcode.INVALID_ENVIRONMENT_VAR)

        config_file = os.path.join(os.environ["LORIS_CONFIG"], ".loris_mri", profile_value)
        if not config_file.endswith(".py"):
            print(
                f"\n[ERROR   ] {config_file} does not appear to be the python configuration file."
                f" Try using 'database_config.py' instead.\n"
            )
            sys.exit(lib.exitcode.INVALID_ARG)

        if os.path.isfile(config_file):
            sys.path.append(os.path.dirname(config_file))
            self.config_info = __import__(os.path.basename(config_file[:-3]))
        else:
            print(f"\n[ERROR   ] {profile_value} does not exist in {os.environ['LORIS_CONFIG']}.")
            sys.exit(lib.exitcode.INVALID_PATH)

    def check_required_options_are_set(self):
        """
        Check that all options deemed to be required by the option_dict have indeed been set
        when calling the script. If not, exits with error message and show the script's usage.
        """

        for key in self.options_dict:
            opt_value = self.options_dict[key]["value"]
            if self.options_dict[key]['required'] and not opt_value:
                print(f"\n[ERROR   ] argument --{key} is required\n")
                print(self.usage)
                sys.exit(lib.exitcode.MISSING_ARG)

    def check_options_file_path_exists(self):
        """
        For the options that have a path in the value, verify that the path provided to the
        script is valid. If not, exits with error message and show the script's usage.
        """

        for key in self.options_dict:
            opt_value = self.options_dict[key]["value"]
            if self.options_dict[key]["is_path"] and opt_value and not os.path.isfile(opt_value):
                print(f"\n[ERROR   ] {opt_value} does not exist. Please provide a valid path for --{key}\n")
                print(self.usage)
                sys.exit(lib.exitcode.INVALID_PATH)

    def check_option_is_in_the_list_of_possible_options(self, opt):
        """
        Checks that the option provided is indeed in the list of possible options.
        If not, exits with error message and show the script's usage.

        :param opt: option to be evaluated
         :type opt: str
        """

        possible_options = list()
        for key in self.options_dict:
            possible_options.append(f"--{key}")
            possible_options.append(f"-{self.options_dict[key]['short_opt']}")

        if opt not in possible_options:
            print(f"\n[ERROR   ] {opt} is not a valid option for the script\n{self.usage}")
            sys.exit(lib.exitcode.INVALID_ARG)

    def check_tarchive_path_upload_id_or_force_set(self):
        """
        Check whether the tarchive_path, upload_id or force option was set in GetOpt.
        Note: only one of those options should be set when calling the script.
        """

        tarchive_path = self.options_dict["tarchive_path"]["value"]
        upload_id = self.options_dict["upload_id"]["value"]
        force = self.options_dict["force"]["value"]
        if not (bool(tarchive_path) + bool(upload_id) + bool(force) == 1):
            print(
                "[ERROR   ] You should either specify an upload_id or a tarchive_path"
                " or use the -force option (if no upload_id or tarchive_path is available"
                " for the NIfTI file to be uploaded). Make sure that you set only one of"
                " those options. Upload will exit now.\n"
            )
            sys.exit(lib.exitcode.MISSING_ARG)

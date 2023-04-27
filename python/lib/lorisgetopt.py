""""""
import getopt

import lib.exitcode
import lib.utilities
import os
import sys

from lib.aws_s3 import AwsS3
from lib.database import Database
from lib.database_lib.config import Config


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
    """


    def __init__(self, usage, options_dict, script_name):
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
        self.check_required_options_are_set()
        self.load_config_file()
        self.tmp_dir = lib.utilities.create_processing_tmp_dir(script_name)

        # ---------------------------------------------------------------------------------------------
        # Establish database connection
        # ---------------------------------------------------------------------------------------------
        self.config_file = self.config_info
        self.verbose = self.options_dict["verbose"]["value"]
        self.db = Database(self.config_file.mysql, self.verbose)
        self.db.connect()

        # ---------------------------------------------------------------------------------------------
        # Load the Config, MRI Upload, Parameter Type and Parameter File database classes
        # ---------------------------------------------------------------------------------------------
        self.config_db_obj = Config(self.db, self.verbose)

        # ---------------------------------------------------------------------------------------------
        # Get Bucket information from Config and connect to bucket
        # ---------------------------------------------------------------------------------------------
        s3_endpoint = self.config_db_obj.get_config("AWS_S3_Endpoint")
        s3_bucket_name = self.config_db_obj.get_config("AWS_S3_Default_Bucket")
        self.s3_obj = None
        if hasattr(self.config_file, 's3'):
            if not self.config_file.s3["aws_access_key_id"] or not self.config_file.s3["aws_secret_access_key"]:
                print(
                    "\n[ERROR   ] missing 'aws_access_key_id' or 'aws_secret_access_key' in config file 's3' object\n"
                )
                sys.exit(lib.exitcode.S3_SETTINGS_FAILURE)
            s3_endpoint = s3_endpoint if s3_endpoint else self.config_file.s3["aws_s3_endpoint_url"]
            s3_bucket_name = s3_bucket_name if s3_bucket_name else self.config_file.s3["aws_s3_bucket_name"]
            if not s3_endpoint or not s3_bucket_name:
                print('\n[ERROR   ] missing configuration for S3 endpoint URL or S3 bucket name\n')
                sys.exit(lib.exitcode.S3_SETTINGS_FAILURE)
            try:
                self.s3_obj = AwsS3(
                    aws_access_key_id=self.config_file.s3["aws_access_key_id"],
                    aws_secret_access_key=self.config_file.s3["aws_secret_access_key"],
                    aws_endpoint_url=s3_endpoint,
                    bucket_name=s3_bucket_name
                )
            except Exception as err:
                print(
                    "[WARNING] Could not connect to an S3 server, "
                    + f"the dataDirBasepath location will be used. Error was\n{err}"
                )

        self.check_options_file_path_exists()

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
            if self.options_dict[key]["is_path"] and opt_value and opt_value.startswith('s3://'):
                if not self.s3_obj:
                    print(
                        f"\n[ERROR   ] No valid S3 connection, please check that S3 is correctly configured"
                        f" in {self.options_dict['profile']['value']} and Config module"
                    )
                    sys.exit(lib.exitcode.S3_SETTINGS_FAILURE)
                try:
                    file_path = os.path.join(self.tmp_dir, os.path.basename(opt_value))
                    self.s3_obj.download_file(opt_value, file_path)
                    self.options_dict[key]["s3_url"] = opt_value
                    self.options_dict[key]["value"] = file_path
                except Exception as err:
                    print(f"[ERROR   ] {opt_value} could not be downloaded from S3 bucket. Error was\n{err}")
                    print(self.usage)
                    sys.exit(lib.exitcode.INVALID_PATH)
            elif self.options_dict[key]["is_path"] and opt_value and not os.path.isfile(opt_value):
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

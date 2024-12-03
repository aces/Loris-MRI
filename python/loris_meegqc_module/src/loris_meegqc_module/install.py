from lib.config_file import load_config
from lib.make_env import make_env

from loris_meegqc_module.database.models.meegqc_file import DbMeegqcFile

# TODO: This script is only used for testing purposes and should not be committed to the final PR.
config = load_config(None)
env = make_env('install-loris-meegqc-module', {}, config, False)

# Create only the User table
DbMeegqcFile.__table__.create(env.db_engine)  # type: ignore

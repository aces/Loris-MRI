import os
from importlib.metadata import entry_points
from typing import Annotated

from fastapi import Depends, FastAPI
from lib.config_file import load_config
from lib.env import Env
from lib.make_env import make_env

# The LORIS API object.
api = FastAPI()

# Load the LORIS configuration.
config = load_config('config.py')


def server_env():
    return make_env('server', {}, config, os.environ['TMPDIR'], False)


EnvDep = Annotated[Env, Depends(server_env)]

for module in entry_points(group='loris-server.modules'):
    print(f"Loading module '{module.name}'")
    module.load()()

import os
from importlib.metadata import entry_points

from fastapi import FastAPI
from lib.config_file import load_config

from loris_server.endpoints.health import health

# Get the LORIS configuration values from the environment.
config_file_name = os.environ.get('LORIS_CONFIG_FILE')
dev_mode         = os.environ.get('LORIS_DEV_MODE') == 'true'

# Load the LORIS configuration.
config = load_config(config_file_name)

# Create the API object.
api = FastAPI(title="LORIS server", debug=dev_mode)

# Attach the LORIS configuration to the API state.
api.state.config = config

# Add the health check route to the API.
api.add_api_route('/health', health, methods=['GET'])

# Load the modules registered into the LORIS server.
for module in entry_points(group='loris_server.loaders'):
    print(f"Loading module '{module.name}'")
    module.load()(api)

#!/bin/bash

# Create a writable directory with links to the imaging dataset files
replicate_raisinbread_for_mcin_dev_vm.pl /data-loris /data/loris

# Run the provided command (usually the integration test command)
exec "$@"

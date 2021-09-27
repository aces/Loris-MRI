# NAME

replicate\_raisinbread\_for\_mcin\_dev\_vm.pl -- Create a local copy of the RaisinBread dataset and
store each file as a symlink to the original dataset found in /data-raisinbread automatically mounted
with all LORIS dev VMs created by MCIN. 

# SYNOPSIS

perl replicate\_raisinbread\_for\_mcin\_dev\_vm.pl `[/path/to/mounted/raisinbread]` `[/path/to/output_dir]` 

# DESCRIPTION

This script takes in two arguments. The first argument is the path to the
RaisinBread dataset (typically `/data-raisinbread`) and the path to the
directory where the replicated dataset will be stored. For example, suppose
the script is run with the following arguments:

perl replicate\_raisinbread\_for\_mcin\_dev\_vm.pl `/data-raisinbread` `/data`

The replicated dataset will be found in `/data/data-raisinbread/` 

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

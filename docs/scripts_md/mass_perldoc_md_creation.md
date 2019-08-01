# NAME

mass\_perldoc\_md\_creation.pl -- Script to mass produce the `.md` files
derived from the documentation of the perl scripts and libraries.

# SYNOPSIS

perl mass\_perldoc\_md\_creation.pl `[options]`

Available options are:

\-profile: name of the config file in `../dicom-archive/.loris_mri`

\-verbose: be verbose (boolean)

# DESCRIPTION

This script will need to be run once per release to make sure the `.md` files
derived from the documentation of the perl scripts and libraries are updated.

If any new script have been added to a given release, make sure to include it
in the variable called `@script_list` at the beginning of the script.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

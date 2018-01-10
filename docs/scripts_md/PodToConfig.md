# NAME

ProdToConfig.pl -- a script that populates the \`Config\` table in the database
with entries from the $profile file.

# SYNOPSIS

perl tools/ProdToConfig.pl \`\[options\]\`

The available option is:

\-profile      : name of the config file in
                `../dicom-archive/.loris_mri`

# DESCRIPTION

This script needs to be run once during the upgrade to LORIS-MRI v18.0.0. Its
purpose is to remove some variables defined in the $profile file to the
Configuration module within LORIS. This script assumes that the LORIS upgrade
patch has been run, with table entries created and set to default values. This
script will then update those values with those that already exist in the
$profile file. If the table entry does not exist in the $profile, its value will
be kept at the value of a new install.

## Methods

### updateConfigFromProd($config\_name, $config\_value)

Function that updates the values in the \`Config\` table for the columns as
specified in the $config\_name

INPUTS   :
 - $config\_name     : Column to set in the Config table
 - $config\_value    : Value to use in the Config table

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

# NAME

imaging\_upload\_file\_cronjob.pl -- a wrapper script that calls the single step
script \`imaging\_upload\_file.pl\` for uploaded scans on which the insertion
pipeline has not been launched.

# SYNOPSIS

perl imaging\_upload\_file\_cronjob.pl \`\[options\]\`

Available options are:

\-profile      : name of the config file in
                `../dicom-archive/.loris_mri`

\-verbose      : if set, be verbose

# DESCRIPTION

The program gets a series of rows from \`mri\_upload\` on which the insertion
pipeline has not been run yet, and launches it.

## Methods

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

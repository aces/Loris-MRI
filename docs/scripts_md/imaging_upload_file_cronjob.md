# NAME

imaging\_upload\_file\_cronjob.pl -- a wrapper script that calls the single step
script `imaging_upload_file.pl` for uploaded scans on which the insertion
pipeline has not been launched.

# SYNOPSIS

perl imaging\_upload\_file\_cronjob.pl `[options]`

Available options are:

\-profile      : Name of the config file in `../dicom-archive/.loris_mri`

\-verbose      : If set, be verbose

# DESCRIPTION

The program gets a series of rows from `mri_upload` on which the insertion
pipeline has not been run yet, and launches it.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

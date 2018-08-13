# NAME

tarchiveLoader -- this script performs the following:

\- validation of the DICOM archive

\- conversion of DICOM datasets into MINC files

\- automated protocol checks against the entries in the `mri_protocol` and
optionally, `mri_protocol_checks` tables.

# SYNOPSIS

perl uploadNeuroDB/tarchiveLoader &lt;/path/to/DICOM-tarchive> `[options]`

Available options are:

\-profile                 : Name of the config file in `../dicom-archive/.loris_mri`

\-force                   : Force the script to run even if the validation
                           has failed

\-reckless                : Upload data to database even if study protocol is
                           not defined or violated

\-globLocation            : Loosen the validity check of the tarchive allowing
                           for the possibility that the tarchive was moved to
                           a different directory

\-newScanner                 : By default a new scanner will be registered if the
                              data you upload requires it. You can risk turning
                              it off

\-keeptmp                 : Keep temporary directory. Make sense if have
                           infinite space on your server

\-xlog                    : Open an xterm with a tail on the current log file

\-verbose                 : If set, be verbose

\-seriesuid               : Only insert this `SeriesUID`

\-acquisition\_protocol    : Suggest the acquisition protocol to use

\-bypass\_extra\_file\_checks: Bypass `extra_file_checks`

# DESCRIPTION

This script interacts with the LORIS database system. It will fetch or modify
contents of the following tables:
`session`, `parameter_file`, `parameter_type`, `parameter_type_category`,
`files`, `mri_staging`, `notification_spool`

## Methods

### logHeader()

Function that adds a header with relevant information to the log file.

# TO DO

\- dicom\_to\_minc: change converter back to perl (or make configurable)

\- add a check for all programms that will be used (exists, but could
  be better....)

\- consider whether to add a check for registered protocols against the
  tarchive db to save a few minutes of converting

\- also add an option to make it interactively query user to learn new protocols

\- add to config file whether or not to autocreate scanners

\- fix comments written as #fixme in the code

# LICENSING

License: GPLv3

# AUTHORS

J-Sebastian Muehlboeck based on Jonathan Harlap\\'s process\_uploads, LORIS
community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

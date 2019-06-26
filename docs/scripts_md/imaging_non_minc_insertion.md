# NAME

imaging\_non\_minc\_insertion.pl -- Insert a non-MINC imaging file into the files table

# SYNOPSIS

perl imaging\_non\_minc\_insertion.pl `[options]`

Available options are:

\-profile       : name of the config file in `../dicom-archive/.loris-mri` (required)

\-file\_path     : file to register into the database (full path from the root
                 directory is required) (required)

\-upload\_id     : ID of the uploaded imaging archive containing the file given as
                 argument with `-file_path` option (required)

\-output\_type   : file's output type (e.g. native, qc, processed...) (required)

\-scan\_type     : file's scan type (from the `mri_scan_type` table) (required)

\-date\_acquired : acquisition date for the file (`YYYY-MM-DD`) (required)

\-scanner\_id    : ID of the scanner stored in the mri\_scanner table (required)

\-coordin\_space : coordinate space of the file to register (e.g. native, linear,
                 nonlinear, nativeT1) (required)

\-reckless      : upload data to the database even if the study protocol
                 is not defined or if it is violated

\-verbose       : boolean, if set, run the script in verbose mode

\-patient\_name  : patient name, if cannot be found in the file name (in the form of
                 `PSCID_CandID_VisitLabel`) (optional)

\-metadata\_file : file that can be read to look for metadata information to attach
                 to the file to be inserted (optional)

# DESCRIPTION

This script inserts a file in the files and parameter\_file tables. Optionally, a
metadata JSON file can be provided and that metadata will be stored in the
parameter\_file table.

An example of a JSON metadata file would be:
{
  "tr": 2000,
  "te": 30,
  "slice\_thickness": 2
}

Note that in order to be able to insert a scan with this script, you need to
provide the following information:
\- path to the file
\- upload ID associated to that file
\- output type of that file (native, qc, processed...)
\- the scan type of the file (from mri\_scan\_type)
\- the acquisition date of the file
\- the scanner ID this file was acquired with
\- the coordinate space of the file (native, linear, nonlinear, nativeT1...)

## Methods

### logHeader()

Prints the log file's header with time of insertion and temp directory location.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

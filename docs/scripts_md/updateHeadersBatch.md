# NAME

updateHeadersBatch.pl -- updates DICOM headers for an entire study or a
specific series in a DICOM archive

# SYNOPSIS

perl tools/updateHeadersBatch.pl `[options]` `[/path/to/DICOM/or/TARCHIVE]`

Available options are:

\-keys    : The number of key fields in the spec file, used to define the
			matching... Note that 1 key consists of two columns, the first
			being the field name (formatted as '(XXXX,YYYY)') and the second
			being its value.

\-specfile: The specifications file. Format is one series per line, tab
            separated fields. First field is the series number. Then every
            pair of fields is the DICOM field name (as known to `dcmtk`) and
            new value, respectively.

\-database: Enable `dicomTar`'s database features

\-profile : Name of the config file in `../dicom-archive/.loris_mri`

\-verbose : Be verbose

\-version : Print version and revision number and exit

# DESCRIPTION

A script that updates DICOM headers for an entire study or a specific series
in a DICOM archive. If run with the `-database` option, it will update the
`tarchive` tables with the updated DICOM archive.

# TODO

Make sure this works as expected.

# LICENSING

License: GPLv3

# AUTHORS

Jonathan Harlap, LORIS community <loris.info@mcin.ca> and McGill Centre for
Integrative Neuroscience

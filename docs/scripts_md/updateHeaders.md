# NAME

updateHeaders.pl -- updates DICOM headers for an entire study or a specific series
in a DICOM archive

# SYNOPSIS

perl tools/updateHeaders.pl `[options]` `[/path/to/DICOM/or/TARCHIVE]`

Available options are:

\-series  : applies the update only to the series with the specified series number

\-set     : set a header field to a value (-set &lt;field name> &lt;value>). Field name
		   should be specified either as '(xxxx,yyyy)' or using names recognized
		   by dcmtk. May be called more than once.

\-database: Enable `dicomTar`'s database features

\-profile : Name of the config file in `../dicom-archive/.loris_mri`

\-verbose : Be verbose

\-version : Print version and revision number and exit

# DESCRIPTION

A script that updates DICOM headers for an entire study or a specific series
in a DICOM archive. If run with the `-database` option, it will update the
`tarchive` tables with the updated DICOM archive.

# METHODS

### extract\_tarchive($tarchive, $tempdir)

Extracts the DICOM archive passed as argument in a temporary directory and
returns the extracted DICOM directory.

INPUTS:
  - $tarchive: the DICOM archive to extract
  - $tempdir : the temporary directory to extract the DICOM archive into

RETURNS: the extracted DICOM directory

### update\_file\_headers($file, $setRef)

Updates the headers of a DICOM file given as argument to that function.

INPUTS:
  - $file  : DICOM file in which to update headers information
  - $setRef: set of headers/values to update in the DICOM file

### handle\_version\_option()

Handles the -version option of the GetOpt table.

### handle\_set\_options($opt, $args)

Handle the -set option of the GetOpt table. It makes sure that two arguments are
following the -set option and stores the &lt;field name>/&lt;new value> information into a
`@setList` array.

INPUTS:
  - $opt : the name of the option (a.k.a. -set)
  - $args: array of arguments following the name of the option in the GetOpt table

RETURNS: 0 if did not find two arguments after the `$opt` option, 1 otherwise

### trimwhitespace($string)

Removes leading and trailing spaces in a string.

INPUTS: the string to modify

RETURNS: the string without leading and trailing spaces

# LICENSING

License: GPLv3

# AUTHORS

Jonathan Harlap, LORIS community &lt;loris.info@mcin.ca> and McGill Centre for
Integrative Neuroscience

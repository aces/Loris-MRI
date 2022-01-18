# NAME

dicomSummary.pl -- prints out an informative summary for DICOMs in a given directory

# SYNOPSIS

perl dicomSummary.pl &lt;/PATH/TO/DICOM/DIR> \[ -compare &lt;/PATH/TO/DICOM/COMPARE/DIR> \] \[ -tmp &lt;/PATH/TO/TMP/DIR> \] \`\[options\]\`

Available options are:

\-comparedir: path to another DICOM directory to compare with

\-dbcompare : run a comparison with entries int he database

\-database  : use the database

\-dbreplace : use this option only if the DICOM data changed and need to be updated
             in the database

\-profile   : specify the name of the config file residing in `.loris_mri` of the
             current directory

\-tmp       : to specify a temporary directory. It will contain the summaries if
             used with -noscreen option

\-xdiff     : to see with tkdiff the result of the two folders comparison or the
             comparison with the database content with

\-batch     : run in batch mode if set. Will log differences to a /tmp/diff.log file.

\-verbose   : be verbose if set

\-version   : print CVS version number and exit

# DESCRIPTION

A tool for producing an informative summary for DICOMs in a given directory
(scanner information, acquisitions list, acquisitions parameters...). This tool
can also compare the DICOM data present in two directories or compare the DICOM
data present in a given directory with what is stored in the database.

## METHODS

### read\_db\_metadata($StudyUID)

Accesses the database and gets the path of the file containing the metadata for
the given StudyUID.

INPUT: the DICOM Study Instance UID (StudyUID)

RETURNS: the path of the file containing the metadata for the given StudyUID or
         undef if none is found.

### version\_conflict($StudyUID)

Compares DICOM summary version numbers for a given StudyUID.

INPUT: the DICOM Study Instance UID (StudyUID)

RETURNS: the version number of the DICOM summary found in the database if the
         version is different from the current version of the script, 0 otherwise

### silly\_head()

Print out a header to the DICOM summary.

# LICENSING

License: GPLv3

# AUTHORS

J-Sebastian Muehlboeck,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

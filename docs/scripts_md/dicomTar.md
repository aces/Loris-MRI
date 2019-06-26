# NAME

dicomTar.pl -- archives DICOM data into the LORIS database

# SYNOPSIS

perl dicomTar.pl &lt;/PATH/TO/SOURCE/DICOM> &lt;/PATH/TO/TARGET/DIR> \`\[options\]\`

Available options are:

\-today                  : Use today's date for archive name instead of using
                          acquisition date

\-database               : Use a database if you have one set up for you.
                          Just trying will fail miserably

\-mri\_upload\_update      : Update the `mri_upload` table by inserting the
                          correct `tarchiveID`

\-clobber                : Use this option only if you want to replace the
                          resulting tarball!

\-profile                : Specify the name of the config file which resides in
                          `.loris_mri` in the current directory

\-centerName             : Specify the symbolic center name to be stored
                          alongside the DICOM institution

\-verbose                : Be verbose if set

\-version                : Print CVS version number and exit

# DESCRIPTION

A tool for archiving DICOM data. Point it to a source directory and provide a
target directory which will be the archive location.

\- If the source contains only one valid STUDY worth of DICOM it will create a
  descriptive summary, a (gzipped) DICOM tarball. The tarball with the metadata
  and a logfile will then be retarred into the final `tarchive`.

\- MD5 sums are reported for every step.

\- It can also be used with a MySQL database.

## Methods

### archive\_head()

Function that prints the DICOM archive header

### read\_file($file)

Function that reads file contents into a variable

INPUT: file to be read

RETURNS: file contents

# TO DO

Fix comments written as #fixme in the code.

# LICENSING

License: GPLv3

# AUTHORS

J-Sebastian Muehlboeck,
LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

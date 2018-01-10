# NAME

minc\_deletion.pl -- this script deletes files records from the database, and
archives the actual files. Files to be deleted can be specified either based on
the series UID or the file ID.

# SYNOPSIS

perl minc\_deletion.pl \`\[options\]\`

Available options are:

\-profile    : name of the config file in
                `../dicom-archive/.loris_mri`

\-series\_uid : the series UID of the file to be deleted

\-fileid     : the file ID of the file to be deleted

# DESCRIPTION

The program does the following:

Deletes minc files from Loris by:
  - Moving the existing files (.mnc .nii .jpg .header .raw\_byte.gz) to an
    archive directory
  - Deleting all related data from 2 database tables:
    parameter\_file & files
  - Deleting data from files\_qcstatus & feedback\_mri\_comments
    database tables if the -delqcdata is set. In most cases
    you would want to delete this when the images change
  - Deleting mri\_acquisition\_dates entry if it is the last file
    removed from that session.

Users can use the argument "select" to view the record that could be removed
from the database, or "confirm" to acknowledge that the data in the database
will be deleted once the script executes.

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

Gregory Luneau and the LORIS community <loris.info@mcin.ca> and McGill Centre
for Integrative Neuroscience

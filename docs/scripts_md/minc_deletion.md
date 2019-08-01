# NAME

minc\_deletion.pl -- this script deletes files records from the database, and
deletes and archives the backend files stored in `/data/$PROJECT/data/assembly/`.
Files to be deleted can be specified either based on the series UID or the file
ID.

# SYNOPSIS

perl minc\_deletion.pl `[options]`

Available options are:

\-profile   : name of the config file in `../dicom-archive/.loris_mri`

\-series\_uid: the series UID of the file to be deleted

\-fileid    : the file ID of the file to be deleted

# DESCRIPTION

This program deletes MINC files from LORIS by:
  - Moving the existing files (`.mnc`, `.nii`, `.jpg`, `.header`,
    `.raw_byte.gz`) to the archive directory: `/data/$PROJECT/data/archive/`
  - Deleting all related data from `parameter_file` & `files` tables
  - Deleting data from `files_qcstatus` and `feedback_mri_comments`
    database tables if the `-delqcdata` option is set. In most cases
    you would want to delete this when the images change
  - Deleting `mri_acquisition_dates` entry if it is the last file
    removed from that session.

Users can use the argument `select` to view the record that could be removed
from the database, or `confirm` to acknowledge that the data in the database
will be deleted once the script executes.

# LICENSING

License: GPLv3

# AUTHORS

Gregory Luneau,
LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

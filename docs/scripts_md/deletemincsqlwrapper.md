# NAME

deletemincsqlqrapper.pl -- This script is a wrapper for deleting multiple MINC
files at a time and optionally re-inserting them. It will pause for confirmation
before deleting. **Projects should modify the query as needed to suit their
needs**.

# SYNOPSIS

perl tools/example\_scripts/deletemincsqlqrapper.pl `[options]`

Available options are:

\-profile      : Name of the config file in
                `../../dicom-archive/.loris_mri`

\-insertminc   : Re-insert the deleted MINC

# DESCRIPTION

This is an **example** script that does the following:
 - Deletes multiple MINC files fitting a common criterion from the database.
 - Provides the option to re-insert deleted scans with their series UID when
   using the `-insertminc` flag.

**Notes:**
 - **Projects should modify the query as they see fit to suit their needs**.
 - For the example query provided (in `$queryF`), all inserted scans with types
   like `t1` or `t2`, having a `slice thickness` in the range of `4 mm` will
   be deleted.
    - A use-case of this deletion query might be that initially the project did
    not exclude `t1` or `t2` modalities having 4 mm slice thickness, and
    subsequently, the study `mri_protocol` table has been changed to add
    tighter checks on slice thickness.

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

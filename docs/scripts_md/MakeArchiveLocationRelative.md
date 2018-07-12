# NAME

MakeArchiveLocationRelative.pl -- Removes the root directory from the
`ArchiveLocation` field in the `tarchive` table to make the path to the
DICOM archive relative.

# SYNOPSIS

perl MakeArchiveLocationRelative.pl `[options]`

Available option is:

\-profile: name of the config file in `../dicom-archive/.loris_mri`

# DESCRIPTION

This script will remove the root directory from the `ArchiveLocation` field
in the `tarchive` table to make the `.tar` path a relative one. This should
be used once to remove the root directory if the `tarchive` table still has
some `ArchiveLocation` paths stored from the root directory.

## Methods

### getTarchiveList($dbh, $tarchiveLibraryDir)

This function will grep all the `TarchiveID` and associated `ArchiveLocation`
present in the `tarchive` table and will create a hash of this information
including new `ArchiveLocation` to be inserted into the database.

INPUTS:
  - $dbh               : database handle
  - $tarchiveLibraryDir: location of the `tarchive` directory

RETURNS: hash with tarchive information and new archive location

### updateArchiveLocation($dbh, %tarchive\_list)

This function will update the `tarchive` table with the new `ArchiveLocation`.

INPUTS:
  - $dbh          : database handle
  - %tarchive\_list: hash with `tarchive` information.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

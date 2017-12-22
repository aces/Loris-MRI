# NAME

MakeArchiveLocationRelative.pl -- Removes the root directory from the
`ArchiveLocation` field in the `tarchive` table to make the path to the
tarchive relative.

# SYNOPSIS

perl MakeArchiveLocationRelative.pl `[options]`

Available option is:

\-profile: name of the config file in ../dicom-archive/.loris\_mri

# DESCRIPTION

This script will remove the root directory from the ArchiveLocation field
in the tarchive table to make path to the tarchive relative. This should
be used once, when updating the LORIS-MRI code.

## Methods

### getTarchiveList($dbh, $tarchiveLibraryDir)

This function will grep all the TarchiveID and associated ArchiveLocation
present in the tarchive table and will create a hash of this information
including new ArchiveLocation to be inserted into the DB.

INPUT: database handle, tarchives location

RETURNS: hash with tarchive information and new archive location

### updateArchiveLocation($dbh, %tarchive\_list)

This function will update the tarchive table with the new ArchiveLocation.

INPUT: database handle, hash with tarchive information.

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

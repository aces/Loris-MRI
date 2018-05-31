# NAME

MakeArchiveLocationRelative.pl -- Removes the root directory from the
`ArchiveLocation` field in the `tarchive` table to make the path to the
tarchive relative.

# SYNOPSIS

perl MakeArchiveLocationRelative.pl `[options]`

Available option is:

\-profile: name of the config file in ../dicom-archive/.loris\_mri

# DESCRIPTION

This script will remove the root directory from the `ArchiveLocation` field
in the `tarchive` table to make the `.tar` path a relative one. This should
be used once to remove the root directory if the `tarchive` table still has
some `ArchiveLocation` paths stored from the root directory.

## Methods

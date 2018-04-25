# NAME

database\_files\_update.pl -- Updates path stored in `files` and
`parameter_file` tables so that they are relative to `data_dir`

# SYNOPSIS

perl database\_files\_update.pl `[options]`

Available option is:

\-profile: name of the config file in ../dicom-archive/.loris\_mri

# DESCRIPTION

This script updates the path stored in the `files` and `parameter_file`
tables to remove the `data_dir` part of the path for security improvements.

## Methods

### get\_minc\_files($data\_dir, $dbh)

Gets the list of MINC files to update the location in the `files` table.

INPUTS: data directory from the `Config` tables, database handle

RETURNS: hash of MINC locations, array of FileIDs

### update\_minc\_location($fileID, $new\_minc\_location, $dbh)

Updates the location of MINC files in the `files` table.

INPUTS: File ID, new MINC relative location, database handle

RETURNS: Number of rows affected by the update (should always be 1)

### get\_parameter\_files($data\_dir, $parameter\_type, $dbh)

Gets list of JIV files to update location in the `parameter_file` table by
removing the root directory from the path.

INPUTS: data directory, parameter type name for the JIV, database handle

RETURNS: hash of JIV file locations, array of FileIDs

### update\_parameter\_file\_location($fileID, $new\_file\_location, ...)

Updates the location of JIV files in the `parameter_file` table.

INPUTS:
  - $fileID           : FileID
  - $new\_file\_location: new location of the JIV file
  - $parameter\_type   : parameter type name for the JIV
  - $dbh              : database handle

RETURNS: number of rows affected by the update (should always be 1)

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

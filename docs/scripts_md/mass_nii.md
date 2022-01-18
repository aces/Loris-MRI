# NAME

mass\_nii.pl -- Generates NIfTI files based on the MINC files available in the
LORIS database and inserts them into the `parameter_file` table.

# SYNOPSIS

perl mass\_nii.pl `[options]`

Available options are:

\-profile  : name of the config file in `../dicom-archive/.loris_mri`

\-minFileID: specifies the minimum `FileID` to operate on

\-maxFileID: specifies the maximum `FileID` to operate on

\-verbose  : be verbose

# DESCRIPTION

This script generates NIfTI images for the inserted MINC files with a `FileID`
between the specified `minFileID` and `maxFileID`.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

# NAME

mass\_pic.pl -- Generates check pic for the LORIS database system

# SYNOPSIS

perl mass\_pic.pl `[options]`

Available options are:

\-profile   : name of the config file in `../dicom-archive/.loris_mri`

\-mincFileID: integer, minimum `FileID` to operate on

\-maxFileID : integer, maximum `FileID` to operate on

\-verbose   : be verbose

# DESCRIPTION

This scripts will generate pics for every registered MINC file that have
a `FileID` from the `files` table between the specified `minFileID`
and `maxFileID`.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

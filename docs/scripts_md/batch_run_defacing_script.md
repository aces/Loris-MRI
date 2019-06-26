# NAME

batch\_run\_defacing\_script.pl -- Run the defacing algorithm on multiple session IDs in parallel using QSUB

# SYNOPSIS

perl batch\_run\_defacing\_script.pl \[-profile file\] < list\_of\_session\_IDs.txt

Available options are:

\-profile: name of config file in ../dicom-archive/.loris\_mri (typically called prod)

# DESCRIPTION

This script runs the defacing pipeline on multiple sessions. The list of
session IDs are provided through a text file (e.g. `list_of_session_IDs.txt`
with one sessionID per line).

An example of what a `list_of_session_IDs.txt` might contain for 3 session IDs
to be defaced:

    123
    124
    125

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

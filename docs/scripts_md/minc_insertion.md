# NAME

minc\_insertion.pl -- Insert MINC files into the LORIS database system

# SYNOPSIS

perl minc\_insertion.pl

# DESCRIPTION

The program inserts MINC files into the LORIS database system. It performs the
four following actions:

\- Loads the created MINC file and then sets the appropriate parameter for
the loaded object:

    (
     ScannerID,  SessionID,      SeriesUID,
     EchoTime,   PendingStaging, CoordinateSpace,
     OutputType, FileType,       TarchiveSource,
     Caveat
    )

\- Extracts the correct acquisition protocol

\- Registers the scan into the LORIS database by changing the path to the MINC
and setting extra parameters

\- Finally sets the series notification

## Methods

### logHeader()

Creates and prints the LOG header.

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

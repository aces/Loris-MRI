# NAME

minc\_insertion.pl -- Insert MINC files into the LORIS database system

# SYNOPSIS

perl minc\_insertion.pl `[options]`

Available options are:

\-profile     : name of the config file in `../dicom-archive/.loris_mri`

\-uploadID    : The upload ID from which this MINC was created

\-reckless    : uploads data to database even if study protocol
               is not defined or violated

\-force       : forces the script to run even if DICOM archive validation failed

\-mincPath    : the absolute path to the MINC file

\-tarchivePath: the absolute path to the tarchive file

\-globLocation: loosens the validity check of the tarchive allowing
               for the possibility that the tarchive was moved
               to a different directory

\-newScanner  : if set \[default\], new scanner will be registered

\-xlog        : opens an xterm with a tail on the current log file

\-verbose     : if set, be verbose

\-acquisition\_protocol    : suggests the acquisition protocol to use

\-create\_minc\_pics        : creates the MINC pics

\-bypass\_extra\_file\_checks: bypasses extra file checks

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

Function that adds a header with relevant information to the log file.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

# NAME

tarchive\_validation.pl -- Validates the tarchive against the one inserted in
the LORIS database.

# SYNOPSIS

perl tarchive\_validation.pl `[options]`

Available options are:

\-profile     : name of the config file in `../dicom-archive/.loris-mri`

\-uploadID    : UploadID associated to the DICOM archive to validate

\-reckless    : upload data to the database even if the study protocol
               is not defined or if it is violated

\-globLocation: loosen the validity check of the tarchive allowing for
               the possibility that the tarchive was moved to a
               different directory

\-newScanner  : boolean, if set, register new scanners into the database

\-verbose     : boolean, if set, run the script in verbose mode

# DESCRIPTION

The program does the following validations:

\- Verification of the DICOM study archive given as an argument to the script
against the one inserted in the database using checksum

\- Verification of the PSC information using whatever field containing the site
string (typically, the patient name or patient ID)

\- Verification of the `ScannerID` of the DICOM study archive (optionally
creates a new scanner entry in the database if necessary)

\- Optionally, creation of candidates as needed and standardization of sex
information when creating the candidates (DICOM uses M/F, LORIS database uses
Male/Female)

\- Check of the `CandID`/`PSCID` match. It's possible that the `CandID`
exists, but that `CandID` and `PSCID` do not correspond to the same
candidate. This would fail further down silently, so we explicitly check that
this information is correct here.

\- Validation of the `SessionID`

\- Optionally, completion of extra filtering on the DICOM dataset, if needed

\- Finally, the `isTarchiveValidated` field in the `mri_upload` table is set
to `TRUE` if the above validations were successful

## Methods

### logHeader()

Function that adds a header with relevant information to the log file.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

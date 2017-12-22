# NAME

register\_processed\_data.pl -- Inserts processed data and link it to the source
data

# SYNOPSIS

perl register\_processed\_data.pl `[options]`

Available options are:

\-profile        : name of config file in ../dicom-archive/.loris\_mri

\-file           : file that will be registered in the database
                   (full path from the root directory is required)

\-sourceFileID   : FileID of the raw input dataset that was processed
                   to obtain the file to be registered in the database

\-sourcePipeline : pipeline name that was used to obtain the file to be
                   registered (example: DTIPrep\_pipeline)

\-tool           : tool name and version that was used to obtain the
                   file to be registered (example: DTIPrep\_v1.1.6)

\-pipelineDate   : date at which the processing pipeline was run

\-coordinateSpace: space coordinate of the file
                   (i.e. linear, nonlinear or native)

\-scanType       : file scan type stored in the `mri_scan_type` table
                   (i.e. QCedDTI, RGBqc, TxtQCReport, XMLQCReport...)

\-outputType     : output type to be registered in the database
                   (i.e. QCed, processed, QCReport)

\-inputFileIDs   : list of input fileIDs used to obtain the file to
                   be registered (each fileID separated by ';')

\-protocolID     : ID of the registered protocol used to process data

Note: All options are required as they will be necessary to insert a file in
the database.

# DESCRIPTION

This script inserts processed data in the files and parameter\_file tables.

## Methods

### getSessionID($sourceFileID, $dbh)

This function returns the sessionID based on the provided sourceFileID.

INPUT: source FileID, database handle

RETURNS: session ID

### getScannerID($sourceFileID, $dbh)

This function gets ScannerID from the `files` table using sourceFileID

INPUT: source FileID, database handle

RETURNS: scanner ID

### getAcqProtID($scanType, $dbh)

This function returns the AcquisitionProtocolID of the file to register in the
database based on scanType in the `mri_scan_type` table.

INPUT: scan type, database handle

RETURNS: acquisition protocol ID

### fetchMincHeader($file, $field)

This function parses the MINC header and look for specific field's value.

INPUT: MINC file, MINC header field

RETURNS: MINC header value

### copy\_file($filename, $subjectIDsref, $scan\_type, $fileref)

Move files to assembly folder.

INPUT: file to copy, subject ID hashref, scan type, file hash ref

RETURNS: file name of the copied file

### getSourceFilename($sourceFileID)

Grep source file name from the database using SourceFileID.

INPUT: ID of the source file

RETURNS: name of the source file

### which\_directory($subjectIDsref)

Determines where the MINC files will go.

INPUT: subject ID hashref

RETURNS: directory where the MINC files will go

### insert\_intermedFiles($fileID, $inputFileIDs, $tool)

Function that will insert into the `files_intermediary` table of the database,
intermediary outputs that were used to obtain the processed file.

INPUT:
  - $fileID      : fileID of the registered processed file
  - $inputFileIDs: array containing the list of input files that were
                    used to obtain the processed file
  - $tool        : tool that was used to obtain the processed file

RETURNS: 1 on success, undef on failure

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

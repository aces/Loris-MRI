# NAME

register\_processed\_data.pl -- Inserts processed data and links it to the source
data

# SYNOPSIS

perl register\_processed\_data.pl `[options]`

Available options are:

\-profile        : name of config file in `../dicom-archive/.loris_mri`

\-file           : file that will be registered in the database
                   (full path from the root directory is required)

\-sourceFileID   : FileID of the raw input dataset that was processed
                   to obtain the file to be registered in the database

\-sourcePipeline : pipeline name that was used to obtain the file to be
                   registered (example: `DTIPrep_pipeline`)

\-tool           : tool name and version that was used to obtain the
                   file to be registered (example: `DTIPrep_v1.1.6`)

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

This script inserts processed data in the `files` and `parameter_file` tables.

## Methods

### getSessionID($sourceFileID, $dbh)

This function returns the `SessionID` based on the provided `sourceFileID`.

INPUTS:
  - $sourceFileID: source FileID
  - $dbh         : database handle

RETURNS: session ID

### getScannerID($sourceFileID, $dbh)

This function gets the `ScannerID` from the `files` table using
`sourceFileID`.

INPUTS:
  - $sourceFileID: source `FileID`
  - $dbh         : database handle

RETURNS: scanner ID

### getAcqProtID($scanType, $dbh)

This function returns the `AcquisitionProtocolID` of the file to register in
the database based on `scanType` in the `mri_scan_type` table.

INPUTS:
  - $scanType: scan type
  - $dbh     : database handle

RETURNS: acquisition protocol ID

### copy\_file($filename, $subjectIDsref, $scan\_type, $fileref)

Moves files to `assembly` folder.

INPUTS:
  - $filename     : file to copy
  - $subjectIDsref: subject ID hash ref
  - $scan\_type    : scan type
  - $fileref      : file hash ref

RETURNS: file name of the copied file

### getSourceFilename($sourceFileID)

Greps source file name from the database using `SourceFileID`.

INPUT: ID of the source file

RETURNS: name of the source file

### which\_directory($subjectIDsref)

Determines where the MINC files will go.

INPUT: subject ID hash ref

RETURNS: directory where the MINC files will go

### insert\_intermedFiles($fileID, $inputFileIDs, $tool)

Function that will insert the intermediary outputs that were used to obtain the
processed file into the `files_intermediary` table of the database.

INPUTS:
  - $fileID      : fileID of the registered processed file
  - $inputFileIDs: array containing the list of input files that were
                    used to obtain the processed file
  - $tool        : tool that was used to obtain the processed file

RETURNS: 1 on success, undef on failure

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

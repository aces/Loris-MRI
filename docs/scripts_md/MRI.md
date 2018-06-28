# NAME

NeuroDB::MRI -- A set of utility functions for performing common tasks
relating to MRI data (particularly with regards to registering MRI
files into the LORIS system)

# SYNOPSIS

    use NeuroDB::File;
    use NeuroDB::MRI;
    use NeuroDB::DBI;

    my $dbh = NeuroDB::DBI::connect_to_db();

    my $file = NeuroDB::File->new(\$dbh);

    $file->loadFileFromDisk('/path/to/some/file');
    $file->setFileData('CoordinateSpace', 'nonlinear');
    $file->setParameter('patient_name', 'Larry Wall');

    my $parameterTypeID = $file->getParameterTypeID('patient_name');
    my $parameterTypeCategoryID = $file->getParameterTypeCategoryID('MRI Header');

# DESCRIPTION

Really a mishmash of utility functions, primarily used by `process_uploads` and
all of its children.

## Methods

### getSubjectIDs($patientName, $scannerID, $dbhr)

Determines the candidate ID and visit label for the subject based on patient
name and (for calibration data) scannerID.

INPUTS: patient name, scanner ID and database handle reference

RETURNS: a reference to a hash containing elements including `CandID`,
`visitLabel` and `visitNo`, or, in the case of failure, `undef`

### subjectIDIsValid($CandID, $PSCID, $dbhr)

Verifies that the subject IDs match.

INPUTS: candidate's CandID, candidate's PSCID and the database handle reference

RETURNS: 1 if the ID pair matches, 0 otherwise

### subjectIDExists($CandID, $dbhr)

Verifies that the subject ID (CandID) exists.

INPUTS: candidate's CandID and the database handle reference

RETURNS: 1 if the ID exists, 0 otherwise

### getScannerCandID($scannerID, $dbhr)

Retrieves the candidate (CandID) for the given scanner.

INPUTS: the scanner ID and the database handle reference

RETURNS: the CandID or (if none exists) undef

### getSessionID($subjectIDref, $studyDate, $dbhr, $objective, ...)

Gets (or creates) the session ID, given CandID and visitLabel (contained
inside the hashref `$subjectIDref`).  Unless `$noStagingCheck` is true, it
also determines whether staging is required using the `$studyDate`
(formatted YYYYMMDD) to determine whether staging is required based on a
simple algorithm:

> \- If there exists a session with the same visit label, then that is
>    the session ID to use.  If any dates (either existing MRI data or
>    simply a date of visit) exist associated with that session, then
>    if they are outside of some (arbitrary) time window, staging is
>    required.  If no dates exist, no staging is required.
>
> \- If no sessions exist, then if there is any other date associated
>    with another session of the same subject within a time window,
>    staging is required.
>
> \- Otherwise, staging is not required.

INPUTS: hash reference of subject IDs, study date, database handle reference,
the objective of the study and a no staging check flag.

RETURNS: a list of two items, (sessionID, requiresStaging)

### checkMRIStudyDates($studyDateJD, $dbhr, @fileIDs)

This method tries to figure out if there may have been labelling problems which
would put the files in a staging area that does not actually exist.

INPUTS: study date, database handle reference and array of fileIDs to check the
study date

RETURNS: 1 if the file requires staging, 0 otherwise

### getObjective($subjectIDsref, $dbhr)

Attempts to determine the SubprojectID  of a timepoint given the subjectIDs
hashref `$subjectIDsref` and a database handle reference `$dbhr`

INPUTS: subjectIDs hashref and database handle reference

RETURNS: the determined objective, or 0

### identify\_scan\_db($center\_name, $objective, $fileref, $dbhr)

Determines the type of the scan described by MINC headers based on
`mri_protocol` table in the database.

INPUTS: center's name, objective of the study, file hashref, database handle
reference

RETURNS: textual name of scan type from the `mri_scan_type` table

### insert\_violated\_scans($dbhr, $series\_desc, $minc\_location, ...)

Inserts scans that do not correspond to any of the defined protocol from the 
`mri_protocol` table into the `mri_protocol_violated_scans` table of the
database.

INPUTS:
  - $dbhr           : database handle reference
  - $series\_desc    : series description of the scan
  - $minc\_location  : minc location of the file
  - $patient\_name   : patient name of the scan
  - $candid         : candidate's CandID
  - $pscid          : candidate's PSCID
  - $visit          : visit of the scan
  - $tr             : repetition time of the scan
  - $te             : echo time of the scan
  - $ti             : inversion time of the scan
  - $slice\_thickness: slice thickness of the image
  - $xstep          : x-step of the image
  - $ystep          : y-step of the image
  - $zstep          : z-step of the image
  - $xspace         : x-space of the image
  - $yspace         : y-space of the image
  - $zspace         : z-space of the image
  - $time           : time dimension of the scan
  - $seriesUID      : seriesUID of the scan

### debug\_inrange($val, $range)

Will evaluate whether the scalar `$value` is in the specified `$range`.

INPUTS: scalar value, scalar range string

RETURNS: 1 if in range, 0 if not in range

### scan\_type\_id\_to\_text($typeID, $dbhr)

Determines the type of the scan identified by its scan type ID.

INPUTS: scan type ID and database handle reference

RETURNS: Textual name of scan type

### scan\_type\_text\_to\_id($type, $dbhr)

Determines the type of the scan identified by scan type.

INPUTS: scan type and database handle reference

RETURNS: ID of the scan type

### in\_range($value, $range\_string)

Determines whether numerical value falls within the range described by range
string. Range string is a comma-separated list of range units. A single range
unit follows the syntax either "X" or "X-Y".

INPUTS: numerical value and the range to use

RETURNS: 1 if the value is in range, 0 otherwise

### floats\_are\_equal($f1, $f2, $nb\_decimals)

Checks whether f1 and f2 are equal (considers only the first nb\_decimals
decimals).

INPUTS: float 1, float 2 and the number of first decimals

RETURNS: 1 if the numbers are relatively equal, 0 otherwise

### range\_to\_sql($field, $range\_string)

Generates a valid SQL WHERE expression to test `$field` against
`$range_string` using the same `$range_string` syntax as `&in_range()`.
It returns a scalar range SQL string appropriate to use as a WHERE condition
(`SELECT ... WHERE range_to_sql(...)`).

INPUTS: scalar field, scalar range string that follows the same format as in
`&in_range()`

RETURNS: scalar range SQL string

### register\_db($file\_ref)

Registers the NeuroDB::File object referenced by `$file_ref` into the database.

INPUT: file hashref

RETURNS: 0 if the file is already registered, the new FileID otherwise

### mapDicomParameters($file\_ref)

Maps DICOM parameters to more meaningful names in the NeuroDB::File object
referenced by `$file_ref`.

INPUT: file hashref

### findScannerID($manufacturer, $model, $serialNumber, ...)

Finds the scannerID for the scanner as defined by `$manufacturer`, `$model`,
`$serialNumber`, `$softwareVersion`, using the database attached to the DBI
database handle reference `$dbhr`. If no scannerID exists, one will be
created.

INPUTS:
  - $manufacturer   : scanner's manufacturer
  - $model          : scanner's model
  - $serialNumber   : scanner's serial number
  - $softwareVersion: scanner's software version
  - $centerID       : scanner's center ID
  - $dbhr           : database handle reference
  - $register\_new   : if set, will call the function `&registerScanner`

RETURNS: (int) scanner ID

### registerScanner($manufacturer, $model, $serialNumber, ...)

Registers the scanner as defined by `$manufacturer`, `$model`,
`$serialNumber`, `$softwareVersion`, into the database attached to the DBI
database handle reference `$dbhr`.

INPUTS:
  - $manufacturer   : scanner's manufacturer
  - $model          : scanner's model
  - $serialNumber   : scanner's serial number
  - $softwareVersion: scanner's software version
  - $centerID       : scanner's center ID
  - $dbhr           : database handle reference

RETURNS: (int) scanner ID

### createNewCandID($dbhr)

Creates a new CandID.

INPUT: database handle reference

RETURNS: (int) CandID

### getPSC($patientName, $dbhr)

Looks for the site alias using the `session` table `CenterID` as 
a first resource, for the cases where it is created using the front-end,
otherwise, find the site alias in whatever field (usually `patient_name` 
or `patient_id`) is provided, and return the `MRI_alias` and `CenterID`.

INPUTS: patient name, database handle reference

RETURNS: a two element array:
  - first is the MRI alias of the PSC or "UNKN"
  - second is the centerID or 0

### compute\_hash($file\_ref)

Semi-intelligently generates a hash (MD5 digest) for the NeuroDB::File object
referenced by `$file_ref`.

INPUT: file hashref

RETURNS: the generated MD5 hash

### is\_unique\_hash($file\_ref)

Determines if the file is unique using the hash (MD5 digest) from the
NeuroDB::File object referenced by `$file_ref`.

INPUT: file hashref

RETURNS: 1 if the file is unique (or if hashes are not being tracked) or 0
otherwise.

### make\_pics($file\_ref, $data\_dir, $dest\_dir, $horizontalPics)

Generates check pics for the Imaging Browser module for the `NeuroDB::File`
object referenced by `$file_ref`.

INPUTS:
  - $file\_ref      : file hash ref
  - $data\_dir      : data directory (`/data/$PROJECT/data` typically)
  - $dest\_dir      : destination directory (`/data/$PROJECT/data/pic`
                     typically)
  - $horizontalPics: boolean, whether to create horizontal pics (1) or not (0)

RETURNS: 1 if the pic was generated or 0 otherwise.

### make\_jiv($file\_ref, $data\_dir, $dest\_dir)

Generates JIV data for the Imaging Browser module for the `NeuroDB::File`
object referenced by `$file_ref`.

INPUTS:
  - $file\_ref      : file hash ref
  - $data\_dir      : data directory (`/data/$PROJECT/data` typically)
  - $dest\_dir      : destination directory (`/data/$PROJECT/data/jiv`
                     typically)

RETURNS: 1 if the JIV data was generated or 0 otherwise.

### make\_nii($fileref, $data\_dir)

Creates NIfTI files associated with MINC files and append its path to the
parameter\_file table using the parameter\_type "check\_nii\_filename".

INPUTS: file hashref and data directory (typically `/data/project/data`)

### make\_minc\_pics($dbhr, $TarchiveSource, $profile, $minFileID, ...)

Creates pics associated with MINC files.

INPUTS:
  - $dbhr          : database handle reference
  - $TarchiveSource: tarchiveID of the DICOM study
  - $profile       : the profile (typically named `prod`)
  - $minFileID     : smaller FileID to be used to run `mass_pic.pl`
  - $debug         : boolean, whether in debug mode (1) or not (0)
  - $verbose       : boolean, whether in verbose mode (1) or not (0)

### DICOMDateToUnixTimestamp($dicomDate>

Converts a DICOM date field (YYYYMMDD) into a unix timestamp.

INPUT: DICOM date to convert

RETURNS: a unix timestamp (integer) or 0 if something went wrong

### lookupCandIDFromPSCID($pscid, $dbhr)

Looks up the CandID for a given PSCID.

INPUTS: candidate's PSCID, database handle reference

RETURNS: the CandID or 0 if the PSCID does not exist

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT AND LICENSE

Copyright (c) 2003-2004 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

# AUTHORS

Jonathan Harlap <jharlap@bic.mni.mcgill.ca>,
LORIS community <loris.info@mcin.ca>  
and McGill Centre for Integrative Neuroscience

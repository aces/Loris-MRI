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

### getSubjectIDs($patientName, $scannerID, $dbhr, $db)

Determines the candidate ID and visit label for the subject based on patient
name and (for calibration data) scanner ID.

INPUTS:
  - $patientName: patient name
  - $scannerID  : scanner ID
  - $dbhr       : database handle reference
  - $db         : database object

RETURNS: a reference to a hash containing elements including `CandID`,
`visitLabel` and `visitNo`, or, in the case of failure, `undef`

### subjectIDIsValid($CandID, $PSCID, $visit\_label, $dbhr, $create\_visit\_label)

Verifies that the subject IDs match.

INPUTS:
  - $candID            : candidate's `CandID`
  - $pscid             : candidate's `PSCID`
  - $visit\_label       : visit label
  - $dbhr              : the database handle reference
  - $create\_visit\_label: boolean, if true, will create the visit label

RETURNS: 1 if the ID pair matches, 0 otherwise

### subjectIDExists($CandID, $dbhr)

Verifies that the subject ID (`CandID`) exists.

INPUTS:
  - $candID: candidate's `CandID`
  - $dbhr  : the database handle reference

RETURNS: 1 if the ID exists, 0 otherwise

### getScannerCandID($scannerID, $db)

Retrieves the candidate (`CandID`) for the given scanner.

INPUTS: the scanner ID and the database object

RETURNS: the `CandID` or (if none exists) undef

### getSessionID($subjectIDref, $studyDate, $dbhr, $objective, $noStagingCheck)

Gets (or creates) the session ID, given CandID and visitLabel (contained
inside the hashref `$subjectIDref`). 

INPUTS:
  - $subjectIDref: hash reference of subject IDs
  - $studyDate   : study date
  - $dbhr        : database handle reference
  - $objective   : the objective of the study
  - $db          : database object

RETURNS: the session ID of the visit

### getObjective($subjectIDsref, $dbhr)

Attempts to determine the `SubprojectID` of a timepoint given the subject IDs
hash ref `$subjectIDsref` and a database handle reference `$dbhr`

INPUTS:
  - $subjectIDsref: subjectIDs hashref
  - $dbhr         : database handle reference

RETURNS: the determined objective, or 0

### identify\_scan\_db($center\_name, $objective, $fileref, $dbhr, $db, $minc\_location)

Determines the type of the scan described by MINC headers based on
`mri_protocol` table in the database.

INPUTS:
  - $center\_name   : center's name
  - $objective     : objective of the study
  - $fileref       : file hash ref
  - $dbhr          : database handle reference
  - $db            : database object
  - $minc\_location : location of the MINC files

RETURNS: textual name of scan type from the `mri_scan_type` table

### insert\_violated\_scans($dbhr, $series\_desc, $minc\_location, $patient\_name, $candid, $pscid, $visit, $tr, $te, $ti, $slice\_thickness, $xstep, $ystep, $zstep, $xspace, $yspace, $zspace, $time, $seriesUID)

Inserts scans that do not correspond to any of the defined protocol from the
`mri_protocol` table into the `mri_protocol_violated_scans` table of the
database.

INPUTS:
  - $dbhr           : database handle reference
  - $series\_desc    : series description of the scan
  - $minc\_location  : location of the MINC file
  - $patient\_name   : patient name of the scan
  - $candid         : candidate's `CandID`
  - $pscid          : candidate's `PSCID`
  - $visit          : visit of the scan
  - $tr             : repetition time of the scan
  - $te             : echo time of the scan
  - $ti             : inversion time of the scan
  - $slice\_thickness: slice thickness of the image
  - $xstep          : `x-step` of the image
  - $ystep          : `y-step` of the image
  - $zstep          : `z-step` of the image
  - $xspace         : `x-space` of the image
  - $yspace         : `y-space` of the image
  - $zspace         : `z-space` of the image
  - $time           : time dimension of the scan
  - $seriesUID      : `SeriesUID` of the scan
  - $tarchiveID     : `TarchiveID` of the DICOM archive from which this file is derived
  - $image\_type     : the `image_type` header value of the image

### scan\_type\_id\_to\_text($typeID, $db)

Determines the type of the scan identified by its scan type ID.

INPUTS:
  - $typeID: scan type ID
  - $db    : database object

RETURNS: Textual name of scan type

### scan\_type\_text\_to\_id($type, $dbhr)

Determines the type of the scan identified by scan type.

INPUTS:
  - $type: scan type
  - $db  : database object

RETURNS: ID of the scan type

### in\_range($value, $range\_string)

Determines whether numerical value falls within the range described by range
string. Range string is a single range unit which follows the syntax
"X" or "X-Y".

Note that if `$range_string`="-", it means that the value in the database are
NULL for both the MIN and MAX columns, therefore we do not want to restrict the
range for this field and the function will return 1.

INPUTS:
  - $value       : numerical value to evaluate
  - $range\_string: the range to use

RETURNS: 1 if the value is in range or the range is undef, 0 otherwise

### floats\_are\_equal($f1, $f2, $nb\_decimals)

Checks whether float 1 and float 2 are equal (considers only the first
`$nb_decimals` decimals).

INPUTS:
  - $f1         : float 1
  - $f2         : float 2
  - $nb\_decimals: the number of first decimals

RETURNS: 1 if the numbers are relatively equal, 0 otherwise

### register\_db($file\_ref)

Registers the `NeuroDB::File` object referenced by `$file_ref` into the
database.

INPUT: file hash ref

RETURNS: 0 if the file is already registered, the new `FileID` otherwise

### mapDicomParameters($file\_ref)

Maps DICOM parameters to more meaningful names in the `NeuroDB::File` object
referenced by `$file_ref`.

INPUT: file hash ref

### findScannerID($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr, $register\_new, $db)

Finds the scanner ID for the scanner as defined by `$manufacturer`, `$model`,
`$serialNumber`, `$softwareVersion`, using the database attached to the DBI
database handle reference `$dbhr`. If no scanner ID exists, one will be
created.

INPUTS:
  - $manufacturer   : scanner's manufacturer
  - $model          : scanner's model
  - $serialNumber   : scanner's serial number
  - $softwareVersion: scanner's software version
  - $centerID       : scanner's center ID
  - $dbhr           : database handle reference
  - $register\_new   : if set, will call the function `&registerScanner`
  - $db             : database object

RETURNS: (int) scanner ID

### registerScanner($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr, $db)

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
  - $db             : database object

RETURNS: (int) scanner ID

### createNewCandID($dbhr)

Creates a new `CandID`.

INPUT: database handle reference

RETURNS: `CandID` (int)

### getPSC($patientName, $dbhr, $db)

Looks for the site alias using the `session` table `CenterID` as
a first resource, for the cases where it is created using the front-end,
otherwise, find the site alias in whatever field (usually `patient_name`
or `patient_id`) is provided, and return the `MRI_alias` and `CenterID`.

INPUTS:
  - $patientName: patient name
  - $dbhr       : database handle reference
  - $db         : database object

RETURNS: a two element array:
  - first is the MRI alias of the PSC or "UNKN"
  - second is the `CenterID` or 0

### compute\_hash($file\_ref)

Semi-intelligently generates a hash (MD5 digest) for the `NeuroDB::File` object
referenced by `$file_ref`.

INPUT: file hash ref

RETURNS: the generated MD5 hash

### is\_unique\_hash($file\_ref)

Determines if the file is unique using the hash (MD5 digest) from the
`NeuroDB::File` object referenced by `$file_ref`.

INPUT: file hashref

RETURNS: 1 if the file is unique (or if hashes are not being tracked) or 0
otherwise.

### make\_pics($file\_ref, $data\_dir, $dest\_dir, $horizontalPics)

Generates check pics for the Imaging Browser module for the `NeuroDB::File`
object referenced by `$file_ref`.

INPUTS:
  - $file\_ref      : file hash ref
  - $data\_dir      : data directory (e.g. `/data/$PROJECT/data`)
  - $dest\_dir      : destination directory (e.g. `/data/$PROJECT/data/pic`)
  - $horizontalPics: boolean, whether to create horizontal pics (1) or not (0)
  - $db            : database object used to interact with the database.

RETURNS: 1 if the pic was generated or 0 otherwise.

### make\_nii($fileref, $data\_dir)

Creates NIfTI files associated with MINC files and append its path to the
`parameter_file` table using the `parameter_type` `check_nii_filename`.

INPUTS:
  - $fileref : file hash ref
  - $data\_dir: data directory (e.g. `/data/$PROJECT/data`)

### create\_dwi\_nifti\_bval\_file($file\_ref, $bval\_file)

Creates the NIfTI `.bval` file required for DWI acquisitions based on the
returned value of `acquisition:bvalues`.

INPUTS:
  - $file\_ref : file hash ref
  - $bval\_file: path to the `.bval` file to write into

RETURNS:
  - undef if no `acquisition:bvalues` were found (skipping the creation
    of the `.bval` file since there is nothing to write into)
  - 1 after the `.bval` file was created

### create\_dwi\_nifti\_bvec\_file($file\_ref, $bvec\_file)

Creates the NIfTI `.bvec` file required for DWI acquisitions based on the
returned value of `acquisition:direction_x`, `acquisition:direction_y` and
`acquisition:direction_z`.

INPUTS:
  - $file\_ref : file hash ref
  - $bvec\_file: path to the `.bvec` file to write into

RETURNS:
  - undef if no `acquisition:direction_x`, `acquisition:direction_y` and
    `acquisition:direction_z` were found (skipping the creation
    of the `.bvec` file since there is nothing to write into)
  - 1 after the `.bvec` file was created

### make\_minc\_pics($dbhr, $TarchiveSource, $profile, $minFileID, $debug, $verbose)

Creates pics associated with MINC files.

INPUTS:
  - $dbhr          : database handle reference
  - $TarchiveSource: `TarchiveID` of the DICOM study
  - $profile       : the profile file (typically named `prod`)
  - $minFileID     : smaller `FileID` to be used to run `mass_pic.pl`
  - $debug         : boolean, whether in debug mode (1) or not (0)
  - $verbose       : boolean, whether in verbose mode (1) or not (0)

### DICOMDateToUnixTimestamp($dicomDate>

Converts a DICOM date field (YYYYMMDD) into a unix timestamp.

INPUT: DICOM date to convert

RETURNS: a unix timestamp (integer) or 0 if something went wrong

### lookupCandIDFromPSCID($pscid, $dbhr)

Looks up the `CandID` for a given `PSCID`.

INPUTS:
  - $pscid: candidate's `PSCID`
  - $dbhr : database handle reference

RETURNS: the `CandID` or 0 if the `PSCID` does not exist

### fetch\_minc\_header\_info($minc, $field, $keep\_semicolon, $get\_arg\_name)

Function that fetches header information in MINC file.

INPUTS:
  - $minc : MINC file
  - $field: string to look for in MINC header (or 'all' to grep all headers)
  - $keep\_semicolon: if set, keeps ";" at the end of extracted value
  - $get\_arg\_name  : if set, returns the MINC header field name

RETURNS: value (or header name) of the field found in the MINC header

### isDicomImage(@files\_list)

This method checks whether the files given as an argument are DICOM images or not.
It will return a hash with the file path as keys and true or false as values (the
value will be set to true if the file is a DICOM image, otherwise it will be set to
false).

INPUT: array with full path to the DICOM files

RETURNS:
  - %isDicomImage: hash with file path as keys and true or false as values (true
                   if the file is a DICOM image file, false otherwise)

### get\_trashbin\_file\_rel\_path($file)

Determines and returns the relative path of a file moved to trashbin at the end of
the insertion pipeline.

INPUT: path to a given file

RETURNS: the relative path of the file moved to the trashbin directory

### deleteFiles(@files)

Deletes a set of files from the file system. A warning will be issued for every file
that could not be deleted.

INPUTS:

    - @files: list of files to delete.
    

# TO DO

Fix comments written as #fixme in the code.

# COPYRIGHT AND LICENSE

Copyright (c) 2003-2004 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

# AUTHORS

Jonathan Harlap &lt;jharlap@bic.mni.mcgill.ca>,
LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

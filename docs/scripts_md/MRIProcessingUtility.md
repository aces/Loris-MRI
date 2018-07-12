# NAME

NeuroDB::MRIProcessingUtility -- Provides an interface for MRI processing
utilities

# SYNOPSIS

    use NeuroDB::ProcessingUtility;

    my $utility       = NeuroDB::MRIProcessingUtility->new(
                          \$dbh,    $debug,  $TmpDir,
                          $logfile, $LogDir, $verbose
                        );

    %tarchiveInfo     = $utility->createTarchiveArray(
                          $ArchiveLocation, $globArchiveLocation
                        );

    my ($center_name, $centerID) = $utility->determinePSC(\%tarchiveInfo,0);

    my $scannerID     = $utility->determineScannerID(
                          \%tarchiveInfo, 0,
                          $centerID,      $NewScanner
                        );

    my $subjectIDsref = $utility->determineSubjectID(
                          $scannerID,
                          \%tarchiveInfo,
                          0
                        );

    my $CandMismatchError = $utility->validateCandidate(
                              $subjectIDsref,
                              $tarchiveInfo{'SourceLocation'}
                            );

    $utility->computeSNR($TarchiveID, $ArchLoc, $profile);
    $utility->orderModalitiesByAcq($TarchiveID, $ArchLoc);

# DESCRIPTION

Mishmash of MRI processing utility functions used mainly by the insertion
scripts of LORIS.

## Methods

### new($dbhr, $debug, $TmpDir, $logfile, $verbose) >> (constructor)

Creates a new instance of this class. The parameter \`\\$dbhr\` is a reference
to a DBI database handle, used to set the object's database handle, so that all
the DB-driven methods will work.

INPUT: DBI database handle

RETURNS: new instance of this class.

### writeErrorLog($message, $failStatus, $LogDir)

Writes error log. This is a useful function that will close the log and write
error messages in case of abnormal program termination.

INPUTS: notification message, fail status of the process, log directory

### lookupNextVisitLabel($candID, $dbhr)

Will look up for the next visit label of candidate `CandID`. Useful only if
the visit label IS NOT encoded somewhere in the patient ID or patient name.

INPUTS: candidate's CandID, database handle reference

RETURNS: next visit label found for the candidate

### getFileNamesfromSeriesUID($seriesuid, @alltarfiles)

Will extract from the `tarchive_files` table a list of DICOM files
matching a given SeriesUID.

INPUTS: seriesUID, list of tar files

RETURNS: list of DICOM files corresponding to the seriesUID

### extract\_tarchive($tarchive, $upload\_id, $seriesuid)

Extracts the DICOM archive so that data can actually be uploaded.

INPUTS:
  - $tarchive : path to the archive
  - $upload\_id: upload ID of the study
  - $seriesuid: optionally a series UID

RETURNS: the extracted DICOM directory

### extractAndParseTarchive($tarchive, $upload\_id, $seriesuid)

Extracts and parses the DICOM archive.

INPUTS:
  - $tarchive : path to the archive
  - $upload\_id: upload ID of the study
  - $seriesuid: optionally a series UID

RETURNS:
  - $ExtractSuffix: extract suffix
  - $study\_dir    : extracted study directory
  - $header       : study meta data header

### determineSubjectID($scannerID, $tarchiveInfo, $to\_log, $upload\_id)

Determines subject's ID based on scanner ID and archive information.

INPUTS:
  - $scannerID   : scanner ID,
  - $tarchiveInfo: archive information hashref,
  - $to\_log      : boolean if this step should be logged
  - $upload\_id   : upload ID of the study

RETURNS: subject's ID hashref containing CandID, PSCID and Visit Label
information

### createTarchiveArray($tarchive, $globArchiveLocation)

Creates the tarchive information hashref.

INPUTS: tarchive's path, globArchiveLocation argument specified when running
the insertion scripts

RETURNS: tarchive information hashref

### determinePSC($tarchiveInfo, $to\_log, $upload\_id)

Determines the PSC based on the DICOM archive information hashref.

INPUTS:
  - $tarchiveInfo: archive information hashref
  - $to\_log      : boolean, whether this step should be logged
  - $upload\_id   : upload ID of the study

RETURNS: array of two elements: center name and center ID

### determineScannerID($tarchiveInfo, $to\_log, $centerID, $NewScanner, ...)

Determines which scanner ID was used for DICOM acquisitions.

INPUTS:
  - $tarchiveInfo: archive information hashref
  - $to\_log      : whether this step should be logged
  - $centerID    : center ID
  - $NewScanner  : whether a new scanner entry should be created if the scanner
                   used is a new scanner for the study
  - $upload\_id   : upload ID of the study

RETURNS: scanner ID

### get\_acqusitions($study\_dir, \\@acquisitions)

UNUSED

### computeMd5Hash($file, $upload\_id)

Computes the MD5 hash of a file and makes sure it is unique.

INPUTS: file to use to compute the MD5 hash, upload ID of the study

RETURNS: 1 if the file is unique, 0 otherwise

### getAcquisitionProtocol($file, $subjectIDsref, $tarchiveInfo, ...)

Determines the acquisition protocol and acquisition protocol ID for the MINC
file. If `$acquisitionProtocol` is not set, it will look for the acquisition
protocol in the `mri_protocol` table based on the MINC header information
using `&NeuroDB::MRI::identify_scan_db`. If `$bypass_extra_file_checks` is
true, then it will bypass the additional protocol checks from the
`mri_protocol_checks` table using `&extra_file_checks`.

INPUTS:
  - $file                    : file's information hashref
  - $subjectIDsref           : subject's information hashref
  - $tarchiveInfo            : tarchive's information hashref
  - $center\_name             : center name
  - $minc                    : absolute path to the MINC file
  - $acquisitionProtocol     : acquisition protocol if already knows it
  - $bypass\_extra\_file\_checks: boolean, if set bypass the extra checks
  - $upload\_id               : upload ID of the study

RETURNS: acquisition protocol, acquisition protocol ID, array of extra checks

### extra\_file\_checks($scan\_type, $file, $CandID, $Visit\_Label, $PatientName)

Returns the list of MRI protocol checks that failed. Can't directly insert
this information here since the file isn't registered in the database yet.

INPUTS:
  - $scan\_type  : scan type of the file
  - $file       : file information hashref
  - $CandID     : candidate's CandID
  - $Visit\_Label: visit label of the scan
  - $PatientName: patient name of the scan

RETURNS:
  - pass, warn or exclude flag depending on the worst failed check
  - array of failed checks if any were failed

### update\_mri\_acquisition\_dates($sessionID, $acq\_date)

Updates the mri\_acquisition\_dates table by a new acquisition date `$acq_date`.

INPUTS: session ID, acquisition date

### loadAndCreateObjectFile($minc, $upload\_id)

Loads and creates the object file.

INPUTS: location of the minc file, upload ID of the study

RETURNS: file information hashref

### move\_minc($minc, $subjectIDsref, $minc\_type, $fileref, $prefix, ...)

Renames and moves the MINC file.

INPUTS:
  - $minc           : path to the MINC file
  - $subjectIDsref  : subject's ID hashref
  - $minc\_type      : MINC file information hashref
  - $fileref        : file information hashref
  - $prefix         : study prefix
  - $data\_dir       : data directory (typically /data/project/data)
  - $tarchive\_srcloc: tarchive source location
  - $upload\_id      : upload ID of the study

RETURNS: new name of the MINC file with path relative to `$data_dir`

### registerScanIntoDB($minc\_file, $tarchiveInfo, $subjectIDsref, ...)

Registers the scan into the database.

INPUTS:
  - $minc\_file          : MINC file information hashref
  - $tarchiveInfo       : tarchive information hashref
  - $subjectIDsref      : subject's ID information hashref
  - $acquisitionProtocol: acquisition protocol
  - $minc               : MINC file to register into the database
  - $checks             : failed checks to register with the file
  - $reckless           : boolean, if reckless or not
  - $sessionID          : session ID of the MINC file
  - $upload\_id          : upload ID of the study

RETURNS: acquisition protocol ID of the MINC file

### dicom\_to\_minc($study\_dir, $converter, $get\_dicom\_info, $exclude, ...)

Converts a DICOM study into MINC files.

INPUTS:
  - $study\_dir      : DICOM study directory to convert
  - $converter      : converter to be used
  - $get\_dicom\_info : get DICOM information setting from the Config table
  - $exclude        : which files to exclude from the dcm2mnc command
  - $mail\_user      : mail of the user
  - $upload\_id      : upload ID of the study

### get\_mincs($minc\_files, $upload\_id)

Greps the created MINC files and returns a sorted list of those MINC files.

INPUTS: empty array to store the list of MINC files, upload ID of the study

### concat\_mri($minc\_files)

Concats and removes pre-concat MINC files.

INPUT: list of MINC files to concat

### registerProgs(@toregister)

Register programs.

INPUT: program to register

### moveAndUpdateTarchive($tarchive\_location, $tarchiveInfo, $upload\_id)

Moves and updates the `tarchive` table with the new location of the
`tarchive`.

INPUTS:
  - $tarchive\_location: `tarchive location`,
  - $tarchiveInfo     : `tarchive` information hashref,
  - $upload\_id        : upload ID of the study

RETURNS: the new `tarchive` location

### CreateMRICandidates($subjectIDsref, $gender, $tarchiveInfo, $User, ...)

Registers a new candidate in the candidate table.

INPUTS:
  - $subjectIDsref: subject's ID information hashref
  - $gender       : gender of the candidate
  - $tarchiveInfo : tarchive information hashref
  - $User         : user that is running the pipeline
  - $centerID     : center ID
  - upload\_id     : upload ID of the study

### setMRISession($subjectIDsref, $tarchiveInfo, $upload\_id)

Sets the imaging session ID. This function will call
`&NeuroDB::MRI::getSessionID` which in turn will either:
  - grep sessionID if visit for that candidate already exists, or
  - create a new session if visit label does not exist for that
     candidate yet

INPUTS:
  - $subjectIDsref: subject's ID information hashref
  - $tarchiveInfo : archive information hashref
  - $upload\_id    : upload ID of the study

RETURNS: session ID, if the new session requires staging

### validateArchive($tarchive, $tarchiveInfo, $upload\_id)

Validates the DICOM archive by comparing the MD5 of the `$tarchive file` and
the one stored in the tarchive information hashref `$tarchiveInfo` derived
from the database. The function will exits with an error message if the
tarchive is not validated.

INPUTS:
  - $tarchive    : archive file
  - $tarchiveInfo: archive information hashref
  - $upload\_id   : upload ID of the study

### which\_directory($subjectIDsref, $data\_dir)

Determines where the MINC files to be registered into the database will go.

INPUTS: subject's ID information hashref, data directory (typically
/data/project/data)

RETURNS: the final directory in which the registered MINC files will go
(typically /data/project/data/assembly/CandID/visit/mri/)

### validateCandidate($subjectIDsref, $tarchive\_srcloc)

Check that the candidate's information derived from the patient name field of
the DICOM files is valid (CandID and PSCID of the candidate should correspond
to the same subject in the database).

INPUTS: subject's ID information hashref, tarchive source location

RETURNS: the candidate mismatch error, or undef if the candidate is validated
or a phantom

### computeSNR($tarchiveID, $upload\_id, $profile)

Computes the SNR on the modalities specified in the `getSNRModalities()`
routine of the `$profile` file.

INPUTS:
  - $tarchiveID: archive ID
  - $upload\_id : upload ID of the study
  - $profile   : configuration file (usually prod)

### orderModalitiesByAcq($tarchiveID, $upload\_id)

Order imaging modalities by acquisition number.

INPUTS: archive ID, upload ID of the study

### getUploadIDUsingTarchiveSrcLoc($tarchive\_srcloc)

Gets the upload ID form the `mri_upload` table using the DICOM archive
`SourceLocation` specified in the `tarchive` table.

INPUT: DICOM archive's source location

RETURNS: the found upload ID

### spool($message, $error, $upload\_id, $verb)

Calls the Notify->spool function to log all messages.

INPUTS:
  - $message   : message to be logged in the database
  - $error     : if 'Y' it's an error log,
                 'N' otherwise
  - $upload\_id : the upload\_id
  - $verb      : 'N' for few main messages,
                 'Y' for more messages (developers)

### isValidMRIProtocol()

Ensures no column in the `mri_protocol` nor the `mri_protocol_checks` 
tables has comma-separated values.

RETURNS: 1 on success, 0 on failure

# TO DO

Document the following functions:
  - concat\_mri($minc\_files)
  - registerProgs(@toregister)

Remove the function get\_acqusitions($study\_dir, \\@acquisitions) that is not used

Remove the function isValidMRIProtocol() once the database schema is configured 
to prevent users from entering non-conform entries in the `mri_protocol` table

# BUGS

None reported (or list of bugs)

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

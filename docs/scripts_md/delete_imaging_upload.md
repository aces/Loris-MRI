# NAME

delete\_mri\_upload.pl -- Delete everything that was produced by the imaging pipeline for a given set of imaging uploads

# SYNOPSIS

perl delete\_mri\_upload.pl \[-profile file\] \[-ignore\] \[-nobackup\] \[-protocol\] \[-form\] \[-uploadID lis\_of\_uploadIDs\]

Available options are:

\-profile     : name of the config file in `../dicom-archive/.loris_mri` (defaults to `prod`).

\-ignore      : ignore files whose paths exist in the database but do not exist on the file system.
               Default is to abort if such a file is found, irrespective of whether a backup has been
               requested or not (see `-nobackup`). If this options is used, a warning is issued
               and program execution continues.

\-nobackup    : do not backup the files produced by the imaging pipeline for the upload(s) passed on
               the command line (default is to perform a backup).

\-uploadID    : comma-separated list of upload IDs (found in table `mri_upload`) to delete. Program will 
               abort if the the list contains an upload ID that does not exist. Also, all upload IDs must
               have the same `tarchive` ID (which can be `NULL`).

\-protocol    : delete the imaging protocol(s) in table `mri_processing_protocol` associated to either the
               upload(s) specified via the `-uploadID` option or any file that was produced using this (these)
               upload(s). Let F be the set of files directly or indirectly associated to the upload(s) to delete.
               This option must be used if there is at least one record in `mri_processing_protocol` that is tied
               only to files in F. Protocols that are tied to files not in F are never deleted. If the files in F
               do not have a protocol associated to them, the switch is ignored if used.

\-form        : delete the entries in `mri_parameter_form` associated to the upload(s) passed on
               the command line, if any (default is NOT to delete them).

# DESCRIPTION

This program deletes all the files and database records produced by the imaging pipeline for a given set
of imaging uploads that have the same `TarchiveID` in table `mri_upload`. The script will issue an error
message and exit if multiple upload IDs are passed on the command line and they do not all have the 
same `TarchiveID` (which can be `NULL`) or if one of the upload ID does not exist. The script will remove
the records associated to the imaging upload whose IDs are passed on the command line from the following tables:
`notification_spool`, `tarchive_series`, `tarchive_files`, `files_intermediary`, `parameter_file`
`files`, `mri_violated_scans`, `mri_violations_log`, `MRICandidateErrors`, `mri_upload` and `tarchive`.
In addition, entries in `mri_processing_protocol` and `mri_parameter_form` will be deleted if the switches
`-protocol` and `-form` are used, respectively. The script will also delete from the file system the files 
found in this set of tables (including the archive itself). No deletion will take place and the script will abort
if there is QC information associated to the upload(s) (i.e entries in tables `files_qcstatus` or 
`feedback_mri_comments`). If the script finds a file that is listed in the database but that does not exist on
the file system, the script will issue an error message and exit, leaving the file system and database untouched.
This behaviour can be changed with option `-ignore`. By default, the script will create a backup of all the files
that it plans to delete before actually deleting them. Use option `-nobackup` to perform a 'hard' delete (i.e. no
backup). The backup file name will be `imaging_upload.<TARCHIVE_ID>.tar.gz`. Note that the file paths inside
this backup archive are absolute. To restore the files in the archive, one must use `tar` with option `--absolute-names`.

## Methods

### getMriProcessingProtocolFilesRef($dbh, $filesRef)

Finds the list of `ProcessingProtocolID` to delete, namely those in table
`mri_processing_protocol` associated to the files to delete, and \*only\* to 
those files that are not going to be deleted.

INPUTS:
  - $dbh: database handle reference.
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.

RETURNS:
 - reference on an array that contains the `ProcessingProtocolID` in table `mri_processing_protocol`
   associated to the files to delete. This array has two keys: `ProcessProtocolID` => the protocol 
   process ID found table `mri_processing_protocol` and `FullPath` => the value of `ProtocolFile`
   in the same table.

### hasQcOrComment($dbh, $tarchiveID)

Determines if any of the MINC files associated to the `tarchive` have QC 
information associated to them by looking at the contents of tables 
`files_qcstatus` and `feedback_mri_comments`.

INPUTS:
  - $dbh: database handle reference.
  - $tarchiveID: ID of the DICOM archive (can be 'NULL').

RETURNS:
  - 1 if there is QC information associated to the DICOM archive, 0 otherwise.

### getFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table `files`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.

RETURNS: 
 - an array of hash references. Each hash has three keys: `FileID` => ID of a file in table `files`
   `File` => value of column `File` for the file with the given ID and `FullPath` => absolute path
   for the file with the given ID.

### getIntermediaryFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the intermediary files associated to an archive 
that are listed in table `files_intermediary`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.

RETURNS: 
  - an array of hash references. Each hash has four keys: `IntermedID` => ID of a file in 
  table `files_intermediary`, `FileID` => ID of this file in table `files`, `File` => value
  of column `File` in table `files` for the file with the given ID and `FullPath` => absolute
  path of the file with the given ID.

### getParameterFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Gets the absolute paths of all the files associated to an archive that are listed in table
`parameter_file` and have a parameter type set to `check_pic_filename`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.

RETURNS: 
  - an array of hash references. Each hash has three keys: `FileID` => FileID of a file 
  in table `parameter_file`, `Value` => value of column `Value` in table `parameter_file`
  for the file with the given ID and `FullPath` => absolute path of the file with the given ID.

### getMriProtocolViolatedScansFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table `mri_protocol_violated_scans`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.

RETURNS: 
 - an array of hash references. Each hash has two keys: `minc_location` => value of column `minc_location`
 in table `mri_protocol_violated_scans` for the MINC file found and `FullPath` => absolute path of the MINC
 file found.

### getMriViolationsLogFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table `mri_violations_log`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.

RETURNS: 
 an array of hash references. Each hash has two keys: `MincFile` => value of column
 `MincFile` for the MINC file found in table `mri_violations_log` and `FullPath` => absolute
 path of the MINC file.

### getMRICandidateErrorsFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table `MRICandidateErrors`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.

RETURNS: 
 - an array of hash references. Each hash has two keys: `MincFile` => value of column
 `MincFile` for the MINC file found in table `MRICandidateErrors` and `FullPath` => absolute
 path of the MINC file.

### getBackupFileName

Gets the name of the backup compressed file that will contain a copy of all the files
that the script will delete.

INPUTS:
  - $tarchiveID: ID of the DICOM archive (in table `tarchive`) associated to the upload(s) passed on the command line.

RETURNS: 
  - backup file name.

### setFileExistenceStatus($filesRef)

Checks the list of all the files related to the upload(s) that were found in the database and 
builds the list of those that do not exist on the file system. 

INPUTS:
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.

RETURNS:
  - Reference on the list of files that do not exist on the file system.

### backupFiles($filesRef)

Backs up all the files associated to the archive before deleting them. The backed up files will
be stored in a `.tar.gz` archive where all paths are absolute.

INPUTS:
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.

RETURNS:
  - Reference on the list of files successfully backed up.

### deleteUploadsInDatabase($dbh, $uploadsRef, $filesRef)

This method deletes all information in the database associated to the given upload(s). More specifically, it 
deletes records from tables `notification_spool`, `tarchive_files`, `tarchive_series`, `files_intermediary`,
`parameter_file`, `files`, `mri_protocol_violated_scans`, `mri_violations_log`, `MRICandidateErrors`
`mri_upload` and `tarchive`, `mri_processing_protocol` and `mri_parameter_form` (the later is done only if requested).
It will also set the `Scan_done` value of the scan's session to 'N' for each upload that is the last upload tied to 
that session. All the delete/update operations are done inside a single transaction so either they all succeed or they 
all fail (and a rollback is performed).

INPUTS:
  - $dbh       : database handle.
  - $uploadsRef: reference on a hash of hashes containing the uploads to delete. Accessed like this:
                 `$uploadsRef->{'1002'}->{'TarchiveID'}`(this would return the `TarchiveID` of the `mri_upload`
                 with ID 1002). The properties stored for each hash are: `UploadID`, `TarchiveID`, `ArchiveLocation`
                 and `SessionID`.
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.
  - $deleteForm: whether to delete the `mri_parameter_form` entries associated to the upload(s) passed on the command line.

### deleteUploadsOnFileSystem($filesRef)

This method deletes from the file system all the files associated to the upload(s) passed on the
command line that were found on the file system. The archive found in table `tarchive` tied to all
the upload(s) passed on the command line is also deleted. A warning will be issued for any file that
could not be deleted.

INPUTS:
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.

# NAME

delete\_mri\_upload.pl -- Delete everything that was produced (or part of what was produced) by the imaging pipeline for a given set of imaging uploads

# SYNOPSIS

perl delete\_mri\_upload.pl \[-profile file\] \[-ignore\] \[-nobackup\] \[-protocol\] \[-form\] \[-uploadID list\_of\_uploadIDs\]
            \[-type list\_of\_scan\_types\] \[-defaced\]

Available options are:

\-profile     : name of the config file in `../dicom-archive/.loris_mri` (defaults to `prod`).

\-ignore      : ignore files whose paths exist in the database but do not exist on the file system.
               Default is to abort if such a file is found, irrespective of whether a backup has been
               requested or not (see `-nobackup`). If this option is used, a warning is issued
               and program execution continues.

\-nobackup    : do not backup the files produced by the imaging pipeline for the upload(s) passed on
               the command line (default is to perform a backup).

\-uploadID    : comma-separated list of upload IDs (found in table `mri_upload`) to delete. The program will 
               abort if the list contains an upload ID that does not exist. Also, all upload IDs must
               have the same `tarchive` ID (which can be `NULL`).

\-protocol    : delete the imaging protocol(s) in table `mri_processing_protocol` associated to either the
               upload(s) specified via the `-uploadID` option or any file that was produced using this (these)
               upload(s). Let F be the set of files directly or indirectly associated to the upload(s) to delete.
               This option must be used if there is at least one record in `mri_processing_protocol` that is tied
               only to files in F. Protocols that are tied to files not in F are never deleted. If the files in F
               do not have a protocol associated to them, the switch is ignored if used.

\-form        : delete the entries in `mri_parameter_form` associated to the upload(s) passed on
               the command line, if any (default is NOT to delete them).

\-type        : comma-separated list of scan type names to delete. All the names must exist in table `mri_scan_type` or
               the script will issue an error. This option cannot be used in conjunction with `-defaced`.

\-defaced     : fetch the scan types listed in config setting `modalities_to_delete` and perform a deletion of these scan
               types as if their names were used with option `-type`. Once all deletions are done, set the `SourceFileID`
               and `TarchiveSource` of all the defaced files in table &lt;files> to `NULL` and to the tarchive ID of the 
               upload(s) whose arguments were passed to `-uploadID`, respectively.

# DESCRIPTION

This program deletes an imaging upload or specific parts of it from the database and the file system. There are three
possible ways in which this script can be used:

1\. Delete everything that is associated to an archive. Basically, for uploads on which the MRI pipeline was
successfully run, this removes all records tied to the upload in the following tables:
   a) `notification_spool`
   b) `files`
   c) `tarchive_series` and `tarchive_files`
   d) `mri_protocol_violated_scans`, `MRICandidateErrors` and `mri_violations_log`
   e) `files_intermediary`. 
   f) `parameter_file`
   g) `tarchive`
   h) `mri_upload`
   i) `mri_processing_protocol` if option `-protocol` is used (see below)
   j) `mri_parameter_form` if option `-form` is used (see below)

All the deletions and modifications performed in the database are done as part of a single transaction, so they either
all succeed or a rollback is performed and the database is not modified in any way. The ID of the upload to delete
is specified via option `-uploadID`. More than one upload can be deleted if they all have the same `TarchiveID` 
in table `mri_upload`: option `-uploadID` can take as argument a comma-separated list of upload IDs for this case.
If an upload that is deleted is the only one that was associated to a given session, the script will set the `Scan_done`
value for that session to 'N'. If option `-form` is used, the `mri_parameter_form` and its associated `flag` record 
are also deleted, for each deleted upload. If option `-protocol` is used and if there is a record in table 
`mri_processing_protocol` that is tied only to the deleted upload(s), then that record is also deleted.

`delete_imaging_upload.pl` cannot be used to delete an upload that has an associated MINC file that has been QCed.
In other words, if there is a MINC file tied to the upload that is targeted for deletion and if that MINC file has 
an associated record in table `files_qcstatus` or `feedback_mri_comments`, the script will issue an error message
and exit.

Before deleting any records in the database, the script will verify that all the records in tables a) through j) that 
represent file names (e.g. a record in `files`, a protocol file in `mri_processing_protocol`, etc...) refer to files
that actually exist on the file system. If it finds a record that does not meet that criterium, the script issues an 
error message and exits, leaving the database untouched. To avoid this check, use option `-ignore`. Each time a file
record is deleted, the file it refers to on the file system is also deleted. A backup will be created by 
`delete_imaging_upload.pl` of all the files that were deleted during execution. Option `-nobackup` can be used to 
prevent a backup from being created. If created, the backup file will be named `imaging_upload.<TARCHIVE_ID>.tar.gz`
or `imaging_upload.<TARCHIVE_ID>.tar.gz` if the upload(s) did not have an associated `tarchive`. Note that the file
paths inside this backup archive are absolute. To restore the files in the archive, one must use `tar` with option 
`--absolute-names`.

The script will also create a file that contains a backup of all the information that was deleted or modified from the 
database tables. This backup is created using `mysqldump` and contains an `INSERT` statement for every record erased. 
If sourced back into the database with `mysql`, it should allow the database to be exactly like it was before 
`delete_imaging_upload.pl` was invoked, provided the database was not modified in the meantime. The SQL backup file will
be named `imaging_upload.<TARCHIVE_ID>.sql.gz` or simply `imaging_upload.sql.gz` if the upload(s) did not have
an associated `tarchive`.

2\. Delete specific scan types from an archive. The behaviour of the script is identical to the one described above, except 
   that:
    a) the deletions are limited to MINC files of a specific scan type: use option `-type` with a comma-separated list
       of scan type names to specify which ones.
    b) everything associated to the MINC files deleted in a) is also deleted: this includes the processed files in 
       `files_intermediary`, the records in `mri_violations_log`, `tarchive_series` and `tarchive_files`.
    c) if `-protocol` is used and there is an entry in table `mri_processing_protocol` that is tied only to the files
       deleted in a), then that record is also deleted.
    d) tables `tarchive`, `mri_upload`, `notification_spool`, `MRICandidateErrors` and `mri_parameter_form` are never
       modified.
   Note that option `-type` cannpot be used in conjunction with either option `-form` or option `-defaced`.

3\. Replace MINC files with their defaced counterparts. This is the behaviour obtained when option `-defaced` is used. As far as 
   deletions go, the behaviour of the script in this case is identical to the one described in 2), except that the list of 
   scan types to delete is fetched from the config setting `modalities_to_deface`. Use of option `-defaced` is not permitted
   in conjunction with option `-type` or option `-form`. Once all deletions are made, the script will change the `SourceFileID` 
   of all defaced files to `NULL` and set the `TarchiveSource` of all defaced files to the `TarchiveiD` of the upload(s). 
   This effectively "replaces" the original MINC files with their corresponding defaced versions. Note that that script will issue 
   an error message and abort, leaving the database and file system untouched, if:
       a) A MINC file should have a corresponding defaced file but does not.
       b) A MINC file that has been defaced has an associated file that is not a defaced file.

## Methods

### printExitMessage($uploadIDRef, $filesRef, $scanTypesToDeleteRef, $tarchiveID, $noSQL) 

Prints an appropriate message before exiting. 

INPUTS:
  - $dbh: database handle reference.
  - $filesRef: reference to the array that contains the file informations for all the files
    that are associated to the upload(s) passed on the command line.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.
  - $tarchiveID: ID of the tarchive associated to the upload(s) (will be 'NULL' if none).
  - $noSQL: whether an SQL backup file of the deleted records is needed or not.

### prettyListPrint($listRef, $andOr) 

Pretty prints a list in string form (e.g "1, 2, 3 and 4" or "7, 8 or 9").

INPUTS:
  - $listRef: the list of elements to print, separated by commas.
  - $andOr: whether to join the last element with the rest of the elements using an 'and' or an 'or'.

### getMriProcessingProtocolFilesRef($dbh, $filesRef)

Finds the list of `ProcessingProtocolID` to delete, namely those in table
`mri_processing_protocol` associated to the files to delete, and \*only\* to 
those files that are going to be deleted.

INPUTS:
  - $dbh: database handle reference.
  - $filesRef: reference to the array that contains the file informations for all the files
    that are associated to the upload(s) passed on the command line.

RETURNS:
 - reference on an array that contains the `ProcessProtocolID` in table `mri_processing_protocol`
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

Get the absolute paths of all the files associated to a DICOM archive and are listed in 
table `files`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.
  - $scanTypesToDeleteRef: reference to the array that contains the list of names of scan types to delete.

RETURNS: 
 - an array of hash references. Each hash has three keys: `FileID` => ID of a file in table `files`
   `File` => value of column `File` for the file with the given ID and `FullPath` => absolute path
   for the file with the given ID.

### getIntermediaryFilesRef($dbh, $tarchiveID, $dataDirBasePath, $scanTypesToDeleteRef)

Get the absolute paths of all the intermediary files associated to an archive 
that are listed in table `files_intermediary`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.

RETURNS: 
  - an array of hash references. Each hash has seven keys: `IntermedID` => ID of a file in 
    table `files_intermediary`, `Input_FileID` => ID of the file that was used as input to create 
    the intermediary file, `Output_FileID` ID of the output file, `FileID` => ID of this file in 
    table `files`, `File` => value of column `File` in table `files` for the file with the given 
    ID, `SourceFileID` value of column `SourceFileID` for the intermediary file and 
    `FullPath` => absolute path of the file with the given ID.

### getParameterFilesRef($dbh, $tarchiveID, $dataDirBasePath, $scanTypesToDeleteRef)

Gets the absolute paths of all the files associated to an archive that are listed in table
`parameter_file` and have a parameter type set to `check_pic_filename`, `check_nii_filename`
`check_bval_filename` or `check_bvec_filename`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.

RETURNS: 
  - an array of hash references. Each hash has four keys: `FileID` => FileID of a file 
    in table `parameter_file`, `Value` => value of column `Value` in table `parameter_file`
    for the file with the given ID, `Name` => name of the parameter and `FullPath` => absolute
    path of the file with the given ID.

### getMriProtocolViolatedScansFilesRef($dbh, $tarchiveID, $dataDirBasePath, $scanTypesToDeleteRef)

Get the absolute paths of all the files associated to a DICOM archive that are listed in 
table `mri_protocol_violated_scans`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.

RETURNS: 
 - an array of hash references. Each hash has three keys: `ID` => ID of the record in table
   `mri_protocol_violated_scans`, `minc_location` => value of column `minc_location` in table 
   `mri_protocol_violated_scans` for the MINC file found and `FullPath` => absolute path of the MINC
   file found.

### getMriViolationsLogFilesRef($dbh, $tarchiveID, $dataDirBasePath, $scanTypesToDeleteRef)

Get the absolute paths of all the files associated to an archive that are listed in 
table `mri_violations_log`.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.

RETURNS: 
 an array of hash references. Each hash has three keys: `LogID` => ID of the record in table 
 `mri_violations_log`, `MincFile` => value of column `MincFile` for the MINC file found in table
 `mri_violations_log` and `FullPath` => absolute path of the MINC file.

### getMRICandidateErrorsFilesRef($dbh, $tarchiveID, $dataDirBasePath, $scanTypeToDeleteRef)

Get the absolute paths of all the files associated to a DICOM archive that are listed in 
table `MRICandidateErrors`.

INPUTS:
  - $dbh   : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting `dataDirBasePath`.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.

RETURNS: 
 - an array of hash references. Each hash has three keys: `ID` => ID of the record in the 
   table, `MincFile` => value of column `MincFile` for the MINC file found in table 
   `MRICandidateErrors` and `FullPath` => absolute path of the MINC file.

### getBackupFileName($tarchiveID)

Gets the name of the backup compressed file that will contain a copy of all the files
that the script will delete.

INPUTS:
  - $tarchiveID: ID of the DICOM archive (in table `tarchive`) associated to the upload(s) passed on the command line.

getbackup
RETURNS: 
  - backup file name.

### getSQLBackupFileName($tarchiveID)

Gets the name of the backup compressed file that will contain the SQL statements that can be used
to restore the database to the state it had before the script was invoked.

INPUTS:
  - $tarchiveID: ID of the DICOM archive (in table `tarchive`) associated to the upload(s) passed on the command line.

getbackup
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

### shouldExist($table, $fileRef)

Checks whether a file path in the database refers to a file that should exist on the file system.

INPUTS:
  - $table: name of the table in which the file path was found.
  - $fileRef: reference to the array that contains the file information for a given file.

RETURNS:
  - 0 or 1 depending on whether the file should exist or not.

### backupFiles($filesRef, $tarchiveID, $scanTypesToDeleteRef, $keepProcessed)

Backs up all the files associated to the archive before deleting them. The backed up files will
be stored in a `.tar.gz` archive in which all paths are absolute.

INPUTS:
  - $filesRef: reference to the array that contains the file informations for all the files
    that are associated to the upload(s) passed on the command line.
  - $tarchiveID: ID of the archive associated to the upload(s) passed on the command line.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.
  - $keepDefaced: whether the defaced files should be kept or not.

### shouldDeleteFile($table, $fileRef, $scanTypesToDeleteRef, $keepDefaced)

Checks whether a given file should be deleted or not.

INPUTS:
  - $table: name of the table in which the file path was found.
  - $fileRef: reference to the array that contains the file information for a given file.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.
  - $keepDefaced: whether the defaced files should be kept or not.

RETURNS:
  - 0 or 1 depending on whether the file should be deleted or not.

### deleteUploadsInDatabase$dbh, $uploadsRef, $filesRef, $deleteMriParameterForm, $scanTypesToDeleteRef, $noSQL, $keepDefaced)

This method deletes all information in the database associated to the given upload(s)/scan type combination. 
More specifically, it deletes records from tables `notification_spool`, `tarchive_files`, `tarchive_series`
`files_intermediary`, `parameter_file`, `files`, `mri_protocol_violated_scans`, `mri_violations_log`
`MRICandidateErrors`, `mri_upload`, `tarchive`, `mri_processing_protocol` and `mri_parameter_form` 
(the later is done only if requested). It will also set the `Scan_done` value of the scan's session to 'N' for
each upload that is the last upload tied to that session. All the delete/update operations are done inside a single 
transaction so either they all succeed or they all fail (and a rollback is performed).

INPUTS:
  - $dbh       : database handle.
  - $uploadsRef: reference on a hash of hashes containing the uploads to delete. Accessed like this:
                 `$uploadsRef->{'1002'}->{'TarchiveID'}`(this would return the `TarchiveID` of the `mri_upload`
                 with ID 1002). The properties stored for each hash are: `UploadID`, `TarchiveID`, `ArchiveLocation`
                 and `SessionID`.
  - $filesRef: reference to the array that contains the file informations for all the files
    that are associated to the upload(s) passed on the command line.
  - $deleteMriParameterForm: whether to delete the `mri_parameter_form` entries associated to the upload(s) passed on the command line.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.
  - $noSQL: whether to generate a file that contains SQL statements that can regenerate the deleted records or not.
  - $keepDefaced: whether the defaced files should be kept or not.

### gzipTmpSQLFile($tarchiveID, $tmpSQLFile)

Compresses the file that contains the SQL statements used to restore the deleted records using `gzip`.

INPUTS:
  - $tarchiveID: ID of the DICOM archive associated to the upload(s) passed on the command line.
  - $tmpSQLFile: path of the SQL file that contains the SQL statements used to restore the deleted records.

RETURNS:
  - 0 or 1 depending on whether the file should be deleted or not.

### updateSessionTable($dbh, $uploadsRef, $tmpSQLFile)

Sets to `N` the `Scan_done` column of all `sessions` in the database that do not have an associated upload
after the script has deleted those whose IDs are passed on the command line. The script also adds an SQL statement
in the SQL file whose path is passed as argument to restore the state that the `session` table had before the deletions.

INPUTS:
   - $dbh       : database handle.
   - $uploadsRef: reference on a hash of hashes containing the uploads to delete. Accessed like this:
                 `$uploadsRef->{'1002'}->{'TarchiveID'}`(this would return the `TarchiveID` of the `mri_upload`
                 with ID 1002). The properties stored for each hash are: `UploadID`, `TarchiveID`, `ArchiveLocation`
                 and `SessionID`.
   - $tmpSQLFile: path of the SQL file that contains the SQL statements used to restore the deleted records.

### updateFilesIntermediaryTable($dbh, $tarchiveID, $filesRef, $tmpSQLFile)

Sets the `TarchiveSource` and `SourceFileID` columns of all the defaced files to `$tarchiveID` and `NULL`
respectively. The script also adds an SQL statement in the SQL file whose path is passed as argument to 
restore the state that the defaced files in the `files` table had before the deletions.

INPUTS:
   - $dbh       : database handle.
   - $tarchiveID: ID of the DICOM archive associated to the upload(s) passed on the command line.
   - $filesRef: reference to the array that contains the file informations for all the files
     that are associated to the upload(s) passed on the command line.
   - $tmpSQLFile: path of the SQL file that contains the SQL statements used to restore the deleted records.

### deleteMriParameterForm($dbh, $uploadsRef, $tmpSQLFile)

Delete the entries in `mri_parameter_form` (and associated `flag` entry) for the upload(s) passed on the
command line. The script also adds an SQL statement in the SQL file whose path is passed as argument to 
restore the state that the `mri_parameter_file` and &lt;flag> tables had before the deletions.

INPUTS:
   - $dbh       : database handle.
   - $uploadsRef: reference on a hash of hashes containing the uploads to delete. Accessed like this:
                 `$uploadsRef->{'1002'}->{'TarchiveID'}`(this would return the `TarchiveID` of the `mri_upload`
                 with ID 1002). The properties stored for each hash are: `UploadID`, `TarchiveID`, `ArchiveLocation`
                 and `SessionID`.
   - $tmpSQLFile: path of the SQL file that contains the SQL statements used to restore the deleted records.

### deleteUploadsOnFileSystem($filesRef, $scanTypesToDeleteRef, $keepDefaced)

This method deletes from the file system all the files associated to the upload(s) passed on the
command line that were found on the file system. A warning will be issued for any file that
could not be deleted.

INPUTS:
  - $filesRef: reference to the array that contains the file informations for all the files
    that are associated to the upload(s) passed on the command line.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.
  - $keepDefaced: whether the defaced files should be kept or not.

### getTypesToDelete($dbh, $scanTypeList, $keepDefaced)

Gets the list of names of the scan types to delete. If `-type` was used, then this list is built
using the argument to this option. If `-defaced` was used, then the list is fetched using the config
setting `modalities_to_deface`.

INPUTS:
  - $dbh: database handle.
  - $scanTypeList: comma separated string of scan type names.
  - $keepDefaced: whether the defaced files should be kept or not.

RETURNS:
  - A reference on a hash of the names of the scan types to delete: key => scan type name
    value => 1 or 0 depending on whether the name is valid or not.

### getTarchiveSeriesIDs($dbh, $filesRef)

Gets the list of `TarchiveSeriesID` to delete in table `tarchive_files`.

INPUTS:
  - $dbh: database handle.
  - $filesRef: reference to the array that contains the file informations for all the files
    that are associated to the upload(s) passed on the command line.

RETURNS:
  - A reference on an array containing the `TarchiveSeriesID` to delete.

### deleteTableData($dbh, $table, $key, $keyValuesRef, $tmpSQLBackupFile)

Deletes records from a database table and adds in a file the SQL statements that allow rewriting the
records in the table. 

INPUTS:
  - $dbh: database handle.
  - $table: name of the database table.
  - $key: name of the key used to delete the records.
  - $keyValuesRef: reference on the list of values that field `$key` has for the records to delete.
  - $tmpSQLBackupFile: path of the SQL file that contains the SQL statements used to restore the deleted records.

### updateSQLBackupFile($tmpSQLBackupFile, $table, $key, $keyValuesRef)

Updates the SQL file with the statements to restore the records whose properties are passed as argument.
The block of statements is written at the beginning of the file.

INPUTS:
  - $tmpSQLBackupFile: path of the SQL file that contains the SQL statements used to restore the deleted records.
  - $table: name of the database table.
  - $key: name of the key used to delete the records.
  - $keyValuesRef: reference on the list of values that field `$key` has for the records to delete.

### getInvalidDefacedFiles($dbh, $filesRef, $scanTypesToDeleteRef)

Checks all the MINC files that should have been defaced and makes sure that only the defaced file
is associated to it.

INPUTS:
  - $dbh       : database handle.
  - $filesRef: reference to the array that contains the file informations for all the files
    that are associated to the upload(s) passed on the command line.
  - $scanTypesToDeleteRef: reference to the array that contains the list of scan type names to delete.

RETURNS:
  - The hash of MINC files that were either not defaced (and should have been) or that have more than one
    processed file associated to them. Key => file path (relative), Value => reference on an array that contains the
    list of processed files associated to the MINC file (0, 2, 3, ... entries).

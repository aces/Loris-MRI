# NAME

delete\_mri\_upload.pl -- Delete everything that was produced by the imaging pipeline for a given set of imaging uploads

# SYNOPSIS

perl delete\_mri\_upload.pl \[-profile file\] \[-ignore\] \[-nobackup\] \[-uploadID lis\_of\_uploadIDs\]

Available options are:

\-profile     : name of the config file in `../dicom-archive/.loris_mri` (defaults to `prod`).

\-ignore      : when performing the file backup, ignore files that do not exist or are not readable
               (default is to abort if such a file is found). This option is ignored if `-n` is used.

\-nobackup    : do not backup the files produced by the imaging pipeline for the upload(s) passed on
               the command line (default is to perform a backup).

\-uploadID    : comma-separated list of upload IDs (in table `mri_upload`) to delete.

# DESCRIPTION

This program deletes all the files and database records produced by the imaging pipeline for a given set
of imaging uploads that have the same `TarchiveID` in table `mri_upload`. The script will issue and error
message and exit if multiple upload IDs are passed on the command line and they do not all have the 
same `TarchiveID`. The script will remove the records associated to the imaging upload whose IDs are passed
on the command line from the following tables: `notification_spool`, `tarchive_series`
`tarchive_files`, `files_intermediary`, `parameter_file`, `files`, `mri_violated_scans`
`mri_violations_log`, `MRICandidateErrors`, `mri_upload` and `tarchive`. It will also delete from
the file system the files that are associated to the upload and are listed in tables `files`
`files_intermediary` and `parameter_file`, along with the archive itself, whose path is stored in 
table `tarchive`. The script will abort and will not delete anything if there is QC information
associated to the upload(s) (i.e entries in tables `files_qcstatus` or `feedback_mri_comments`).
If the script finds a file that is listed in the database but that does not exist on the file system or
is not readable, the script will issue an error message and abort, leaving the file system and database
untouched. This behaviour can be changed with option `-ignore`. By default, the script will create a
backup of all the files that it plans to delete before actually deleting them. Use option `-nobackup`
to perform a 'hard' delete (i.e. no backup). The backup file name will be `mri_upload.<UPLOAD_ID>.tar.gz`.
Note that the file paths inside this backup archive are absolute.

## Methods

### hasQcOrComment($dbh, $tarchiveID)

Determines if any of the MINC files associated to the `tarchive` have QC 
information associated to them by looking at the contents of tables 
`files_qcstatus` and `feedback_mri_comments`.

INPUTS:

    - $dbh: database handle reference.
    - $tarchiveID: ID of the DICOM archive.

RETURNS:

    1 if there is QC information associated to the DICOM archive, 0 otherwise.

### getFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table `files`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the DICOM archive.
    - $dataDirBasePath: config value of setting 'dataDirBasePath'.

RETURNS: 

    an array of hash references. Each hash has two keys: 'FileID' => ID of a file in table files
    and 'File' => absolute path of the file with the given ID.

### getIntermediaryFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the intermediary files associated to an archive 
that are listed in table `files_intermediary`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the DICOM archive.
    - $dataDirBasePath: config value of setting 'dataDirBasePath'.

RETURNS: 

    an array of hash references. Each hash has three keys: 'IntermedID' => ID of a file in 
    table files_intermediary , 'FileID' => ID of this file in table files and 
    'File' => absolute path of the file with the given ID.

### getParameterFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Gets the absolute paths of all the files associated to an archive 
that are listed in table `parameter_file` and have a parameter
type set to `check_pic_filename`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the DICOM archive.
    - $dataDirBasePath: config value of setting 'dataDirBasePath'.

RETURNS: 

    an array of hash references. Each hash has two keys: 'FileID' => FileID of a file 
    in table parameter_file and 'Value' => absolute path of the file with the given ID.

### getMriProtocolViolatedScansFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table `mri_protocol_violated_scans`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the DICOM archive.
    - $dataDirBasePath: config value of setting 'dataDirBasePath'.

RETURNS: 

    an array of hash references. Each hash has one key: 'minc_location' => location (absolute path)
    of a MINC file found in table mri_protocol_violated_scans.

### getMriViolationsLogFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table `mri_protocol_violations_log`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the DICOM archive.
    - $dataDirBasePath: config value of setting 'dataDirBasePath'.

RETURNS: 

    an array of hash references. Each hash has one key: 'MincFile' => location (absolute path)
    of a MINC file found in table mri_violations_log.

### getMRICandidateErrorsFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table `MRICandidateErrors`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the DICOM archive.
    - $dataDirBasePath: config value of setting 'dataDirBasePath'.

RETURNS: 

    an array of hash references. Each hash has one key: 'MincFile' => location (absolute path)
    of a MINC file found in table MRICandidateErrors.

### getBackupFileName

Gets the name of the backup compressed file that will contain a copy of all the files
that the script will delete.

INPUTS:

    - $tarchiveID: ID of the DICOM archive (in table tarchive) associated to the upload(s) passed on the command line.

RETURNS: 

    backup file name.

### backupFiles($archiveLocation, $filePathsRef)

Backs up all the files associated to the archive before deleting them. The backed up files will
be stored in a `.tar.gz` archive where all paths are relative to `/` (i.e absolute paths).

INPUTS:

    - $archiveLocation: full path of the archive associated to the upload(s) passed on the
                        command line (computed using the ArchiveLocation value in table 
                        tarchive for the given archive).
    - $filePathsRef: reference to the array that contains the absolute paths of all files found in table
                     files, files_intermediary, parameter_file, mri_protocol_violated_scans
                     mri_violations_log and MRICandidateErrors that are tied to the upload(s) passed
                     on the command line.
    - $tarchiveID: ID of the DICOM archive (in table tarchive) associated to the upload(s) passed on the command line.
                   

### deleteUploadsInDatabase($dbh, $uploadsRef, $tarchiveID, $filePathsRef)

This method deletes all information in the database associated to the given upload(s). More specifically, it 
deletes records from tables `notification_spool`, `tarchive_files`, `tarchive_series`, `files_intermediary`
`parameter_file`, `files`, `mri_protocol_violated_scans`, `mri_violations_log`, `MRICandidateErrors`
`mri_upload` and `tarchive`. It will also set the `Scan_done` value of the scan's session to 'N' for each upload
that is the last upload tied to that session. All the delete/update operations are done inside a single transaction so 
either they all succeed or they all fail (and a rollback is performed).

INPUTS:

    - $dbh       : database handle.
    - $uploadsRef: reference on a hash of hashes containing the uploads to delete. Accessed like this:
                   $uploadsRef->{'1002'}->{'TarchiveID'} (this would return the TarchiveID of the mri_upload
                   with ID 1002). The properties stored for each hash are: UploadID, TarchiveID, ArchiveLocation
                   and SessionID.
    - $tarchiveID: ID of the DICOM archive to delete.
    - $filePathsRef: reference to the array that contains the absolute paths of all files found in table
                     files, files_intermediary, parameter_file, mri_protocol_violated_scans
                     mri_violations_log and MRICandidateErrors that are tied to the upload(s) passed
                     on the command line.
                    

### deleteUploadsOnFileSystem($archiveLocation, $filePathsRef)

This method deletes from the file system all the files in tables `files`, `files_intermediary`
and `parameter_file` associated to the upload(s) passed on the command line. The archive
found in table `tarchive` tied to all the upload(s) passed on the command line is also delete. 
A warning is issued for any file that could not be deleted.

INPUTS:

    - $archiveLocation: full path of the archive associated to the upload(s) passed on the
                        command line (computed using the ArchiveLocation value in table 
                        tarchive for the given archive).
    - $filePathsRef: reference to the array that contains the absolute paths of all files found in table
                     files, files_intermediary, parameter_file, mri_protocol_violated_scans
                     mri_violations_log and MRICandidateErrors that are tied to the upload(s) passed
                     on the command line.
                    

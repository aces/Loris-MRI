# NAME

delete\_mri\_upload.pl -- Delete eveything that was produced by the MRI pipeline for a given MRI upload

# SYNOPSIS

perl delete\_mri\_upload.pl \[-profile file\] \[-i\] \[-n\]

Available options are:

\-profile     : name of the config file in `../dicom-archive/.loris_mri` (defaults to `prod`).

\-i           : when performing the file backup, ignore files that do not exist or are not readable
               (default is to abort if such a file is found). This option is ignored if `-n` is used.

\-n           : do not backup the files produced by the MRI pipeline for this upload (default is to
               perform a backup).

# DESCRIPTION

This program deletes all the files and database records produced by the MRI pipeline for a given 
MRI upload. More specifically, the script will remove the records associated to the MRI upload whose
ID is passed on the command line from the following tables: `notification_spool`, `tarchive_series`
`tarchive_files`, `files_intermediary`, `parameter_file`, `files`, `mri_violated_scans`
`mri_violations_log`, `MRICandidateErrors`, `mri_upload` and `tarchive`. It will also delete from 
the file system the files that are associated to the upload and are listed in tables `files`
`files_intermediary` and `parameter_file`. The script will abort and will not delete anything if there 
is QC information associated to the upload (i.e entries in tables `files_qcstatus` or `feedback_mri_comments`).
If the script finds a file that is listed in the database but that does not exist on the file system or is not
readable, the script will issue an error message and abort, leaving the file system and database untouched. 
This behaviour can be changed with option `-i`. By default, the script will create a backup of all the files 
that it plans to delete before actually deleting them. Use option `-n` to perform a 'hard' delete (i.e. no backup).
The backup file name will be `mri_upload.<UPLOAD_ID`.tar.gz>. Note that the file paths inside this backup archive
are absolute.

## Methods

### hasQcOrComment($dbh, $tarchiveID)

Determines if a tarchive has QC information associated to it by looking at the
contents of tables `files_qcstatus` and `feedback_mri_comments`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the tarchive.

RETURNS:

    1 if there is QC information associated to the archive, 0 otherwise.

### getFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table `files`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the tarchive.
    - $dataDirBasePath: base path of the directory where all the files in table C<files>
                        are located (i.e config value of setting 'dataDirBasePath').

RETURNS: 

    an array of hash references. Each has has two keys: 'FileID' => ID of a file in table C<files>
    and 'File' => absolute path of the file with the given ID.

### getIntermediaryFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the intermediary files associated to an archive 
that are listed in table `files_intermediary`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the tarchive.
    - $dataDirBasePath: base path of the directory where all the files in table C<files>
                        are located (i.e config value of setting 'dataDirBasePath').

RETURNS: 

    an array of hash references. Each hash has three keys: 'IntermedID' => ID of a file in 
    table C<files_intermediary> , 'FileID' => ID of this file in table C<files> and 
    'File' => absolute path of the file with the given ID.

### getPicFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Gets the absolute paths of all the files associated to an archive 
that are listed in table `parameter_file` and have a parameter
type set to `check_pic_filename`.

INPUTS:

    - $dbhr  : database handle reference.
    - $tarchiveID: ID of the tarchive.
    - $dataDirBasePath: base path of the directory where all the files in table C<files>
                        are located (i.e config value of setting 'dataDirBasePath').

RETURNS: 

    an array of hash references. Each hash has two keys: 'FileID' => FileID of a file 
    in table C<parameter_file> and 'Value' => absolute path of the file with the given ID.

### getBackupFileName

Gets the name of the tar compressed file that will contain a backup of all files
that the script will delete.

RETURNS: 

    backup file name.

### backupFiles($uploadId, $archiveLocation, $filesRef, $intermediaryFilesRef, $picFilesRef)

Backs up all the files associated to the archive before deleting them. The backed up files will
be stored in a `.tar.gz` archive where all paths are relative to `/` (i.e absolute paths).

INPUTS:

    - $uploadId  : ID of the upload to delete.
    - $archiveLocation: absolute path of the backed up archive created by the MRI pipeline.
    - $filesRef: reference to the array that contains all files in table C<files> associated to
                 the upload.
    - $intermediaryFilesRef: reference to the array that contains all files in table C<files_intermediary>
                             associated to the upload.
    - $picFilesRef: reference to the array that contains all files in table C<parameter_file>
                    associated to the upload.
                    

### deleteUploadInDatabase($dbh, $uploadID, $tarchiveID, $sessionID, $intermediaryFilesRef, $picFilesRef)

This method deletes all information in the database associated to the given archive. More specifically, it 
deletes records from tables `notification_spool`, `tarchive_files`, `tarchive_series`, `files_intermediary`
`parameter_file`, `files`, `mri_protocol_violated_scans`, `mri_violations_log`, `MRICandidateErrors`
`mri_upload` and `tarchive`. It will also set the CScan\_done> value of the scan's session to 'N' if the upload
is the last upload tied to that session. All the delete/update operations are done inside a single transaction so 
either they all succeed or they all fail (and a rollback is performed).

INPUTS:

    - $dbh       : database handle.
    - $uploadId  : ID of the upload to delete.
    - $tarchiveID: ID of the tarchive to delete.
    - $sessionID : ID of the session associated to the scan,
    - $filesRef: reference to the array that contains all files in table C<files> associated to
                 the upload.
    - $intermediaryFilesRef: reference to the array that contains all files in table C<files_intermediary>
                             associated to the upload.
    - $picFilesRef: reference to the array that contains all files in table C<parameter_file>
                    associated to the upload.
                    

### deleteUploadFiles($archiveLocation, $filesRef, $intermediaryFilesRef, $picFilesRef)

This method deletes form the file system all the files tied to the upload that were listed in
tables `files`, `files_intermediary` and &lt;parameter\_file>, along with the back up of the 
archive created by the MRI pipeline when the upload was processed. A warning is issued for any
file that could not be deleted.

INPUTS:

    - $archiveLocation: full path of the archive backup created by the MRI pipeline when the upload
                        was processed.
    - $filesRef: reference to the array that contains all files in table C<files> associated to
                 the upload.
    - $intermediaryFilesRef: reference to the array that contains all files in table C<files_intermediary>
                             associated to the upload.
    - $picFilesRef: reference to the array that contains all files in table C<parameter_file>
                    associated to the upload.
                    

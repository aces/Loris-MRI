use strict;
use warnings;

package NeuroDB::ExitCodes;

#TODO: POD DOCUMENTATION





#### --- EXIT CODES COMMON TO MOST IMAGING INSERTION SCRIPTS

# script ran successfully
my $SUCCESS = 0; # yeah!! Success!!

# input error checking and setting failures
my $GETOPT_FAILURE          = 1; # if no getOptions were set
my $PROFILE_FAILURE         = 2; # if no profile file specified
my $MISSING_ARG             = 3; # if missing script's argument(s)
my $DB_SETTINGS_FAILURE     = 4; # if DB settings in profile file are not set
my $ARG_FILE_DOES_NOT_EXIST = 5; # if file given as an argument does not exist
                                 # in the file system






#### --- FROM batch_uploads_imageuploader

# validation failures
my $UPLOADED_FILE_TYPE_FAILURE = 10; # if the uploaded file is not a .tgz,
# tar.gz or .zip file
my $PHANTOM_ENTRY_FAILURE      = 11; # if the phantom entry in the text file is
# not 'N' nor 'Y'
my $PNAME_FILENAME_MISMATCH    = 12; # if patient name and beginning of uploaded
# filename does not match
my $PNAME_PHANTOM_MISMATCH     = 13; # if patient name provided in the text file
# but phantom is set to 'Y'






#### --- FROM dicom-archive/dicomTar.pl

# input error checking and setting failures
my $TARGET_EXISTS_NO_CLOBBER = 21; # if tarchive already exists but option
# -clobber was not set

# database related failures
my $TARCHIVE_INSERT_FAILURE  = 22; # if insertion in the tarchive tables failed

# script execution failures
my $UPDATEMRI_UPLOAD_FAILURE = 23; # if updateMRI_Upload.pl execution failed






#### --- FROM uploadNeuroDB/imaging_upload_file.pl

# input error checking and setting failures
my $UPLOAD_ID_PATH_MISMATCH = 1; # if upload path given as an argument does
                                 # not match the path stored in the mri_upload
                                 # table for the UploadID given as an argument
#TODO: should create two different exit codes for that and modify
# ImagingUpload.pm around line 195 to return the proper exit code
my $INVALID_DICOM_CAND_INFO = 1; # if files in tarchive are not all DICOMs or
                                 # if at least one patient name mismatch
                                 # between the one stored in DICOM files and
                                 # the one stored in mri_upload

# script execution failures
my $DICOMTAR_FAILURE       = 1; # if dicomTar.pl execution failed
my $TARCHIVELOADER_FAILURE = 1; # if tarchiveLoader execution failed

my $CLEANUP_UPLOAD_FAILURE = 1; # if removal/clean up of the uploaded file in
                                # the incoming folder failed






#### --- FROM dicom-archive/updateMRI_upload.pl

# validation failures
my $TARCHIVE_ALREADY_UPLOADED = 1; # if the tarchive was already uploaded






#### --- FROM uploadNeuroDB/NeuroDB/MRIProcessingUtility.pm

# database related failures
my $TARCHIVE_NOT_IN_DB        = 1; # if tarchive not found in the database
my $GET_PSC_FAILURE           = 1; # if could not determine PSC from the DB
my $GET_SCANNERID_FAILURE     = 1; # if could not determine scannerID from DB
my $CAND_REGISTRATION_FAILURE = 1; # if candidate registration failed


# file related failures
my $EXTRACT_ARCHIVE_FAILURE = 1; # if extraction of the archive failed
my $CORRUPTED_TARCHIVE      = 1; # if mismatch between md5sum stored in the
                                 # tarchive table and the md5sum of the tarchive
                                 # from the file system

# study related failures
my $GET_SUBJECT_ID_FAILURE = 1; # if the getSubjectIDs function from the
                                # profile does not return subject IDs






#### --- FROM uploadNeuroDB/minc_deletion.pl

# validation failures
my $FILEID_SERIESUID_ARG_FAILURE = 1; # if seriesUID and fileID both provided
                                      # as input to the file (it should always
                                      # be one or the other)






#### --- FROM uploadNeuroDB/minc_insertion.pl

# validation failures
my $INVALID_TARCHIVE   = 1; # if tarchive validation is not set to 1 in the
                            # mri_upload table
my $CANDIDATE_MISMATCH = 1; # if candidate PSCID and CandID do not match
my $FILE_NOT_UNIQUE    = 1; # if (MINC) file is not unique and already inserted
my $UNKNOW_PROTOCOL    = 1; # if could not find acquisition protocol of the MINC
my $PROTOCOL_NOT_IN_PROFILE = 1; # if the acquisition protocol could be
                                 # determined but is not included in the
                                 # isFileToBeRegisteredGivenProtocol function
                                 # of the profile file






#### --- FROM uploadNeuroDB/tarchiveLoader

# script execution failures
my $TARCHIVE_VALIDATION_FAILURE = 1; # if tarchive_validation.pl failed

# file related failures
my $NO_VALID_MINC_CREATED = 1; # if no valid MINC file was created (non-scout)
my $NO_MINC_INSERTED      = 1; # if no MINC files was inserted (invalid study)

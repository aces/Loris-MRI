use strict;
use warnings;

package NeuroDB::ExitCodes;


#### Exit codes common to most imaging insertion scripts

# script ran successfully
my $SUCCESS = 0; # yeah!! Success!!

# input error checking and setting failures
my $GETOPT_FAILURE          = 1; # if no getOptions were set
my $PROFILE_FAILURE         = 1; # if no profile file specified
my $MISSING_ARG             = 1; # if missing script's argument(s)
my $DB_SETTINGS_FAILURE     = 1; # if DB settings in profile file are not set
my $ARG_FILE_DOES_NOT_EXIST = 1; # if file given as an argument does not exist
                                 # in the file system




#### From uploadNeuroDBimaging_upload_file.pl

# input error checking and setting failures
my $MISSING_UPLOAD_ID_ARG   = 1; # TODO maybe just keep MISSING_ARG
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




#### uploadNeuroDB/tarchiveLoader

# script execution failures
my $TARCHIVE_VALIDATION_FAILURE = 1; # if tarchive_validation.pl failed

# file related failures
my $NO_VALID_MINC_CREATED = 1; # if no valid MINC file was created (non-scout)
my $NO_MINC_INSERTED      = 1; # if no MINC files was inserted (invalid study)




#### uploadNeuroDB/minc_insertion.pl

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



#### dicom-archive/dicomTar.pl

# input error checking and setting failures
my $TARGET_EXISTS_NO_CLOBBER = 1; # if tarchive already exists but option
                                  # -clobber was not set

# database related failures
my $TARCHIVE_INSERT_FAILURE  = 1; # if insertion in the tarchive tables failed

# script execution failures
my $UPDATEMRI_UPLOAD_FAILURE = 1; # if updateMRI_Upload.pl execution failed




#### dicom-archive/updateMRI_upload.pl

# validation failures
my $TARCHIVE_ALREADY_UPLOADED = 1; # if the tarchive was already uploaded






# database related failures

my $no_tarchive_in_db       = 1;
my $get_psc_failure         = 1;
my $get_scanner_id_failure  = 1;
my $candidate_registration_failure = 1;

# file related failures

my $extract_archive_failure = 1;
my $corrupted_archive       = 1;

# study related failures

my $get_subject_id_failure = 1;





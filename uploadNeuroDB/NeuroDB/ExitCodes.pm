use strict;
use warnings;

package NeuroDB::ExitCodes;

#TODO: POD DOCUMENTATION





#### --- EXIT CODES COMMON TO MOST IMAGING INSERTION SCRIPTS

# script ran successfully
our $SUCCESS = 0; # yeah!! Success!!

# input error checking and setting failures
our $GETOPT_FAILURE          = 1; # if no getOptions were set
our $PROFILE_FAILURE         = 2; # if no profile file specified
our $MISSING_ARG             = 3; # if missing script's argument(s)
our $DB_SETTINGS_FAILURE     = 4; # if DB settings in profile file are not set
our $ARG_FILE_DOES_NOT_EXIST = 5; # if file given as an argument does not exist
                                  # in the file system






#### --- FROM batch_uploads_imageuploader

# validation failures
our $UPLOADED_FILE_TYPE_FAILURE = 10; # if the uploaded file is not a .tgz,
                                      # tar.gz or .zip file
our $PHANTOM_ENTRY_FAILURE      = 11; # if the phantom entry in the text file is
                                      # not 'N' nor 'Y'
our $PNAME_FILENAME_MISMATCH    = 12; # if patient name and beginning of
                                      # uploaded filename does not match
our $PNAME_PHANTOM_MISMATCH     = 13; # if patient name provided in the text
                                      # file but phantom is set to 'Y'






#### --- FROM dicom-archive/dicomTar.pl

# input error checking and setting failures
our $TARGET_EXISTS_NO_CLOBBER  = 20; # if tarchive already exists but option
                                     # -clobber was not set

# database related failures
our $TARCHIVE_INSERT_FAILURE   = 21; # if insertion in tarchive tables failed

# script execution failures
our $UPDATE_MRI_UPLOAD_FAILURE = 22; # if updateMRI_Upload.pl execution failed






#### --- FROM uploadNeuroDB/imaging_upload_file.pl

# input error checking and setting failures
our $UPLOAD_ID_PATH_MISMATCH = 30; # if upload path given as an argument does
                                   # not match the path stored in the mri_upload
                                   # table for the UploadID given as an argument
our $INVALID_DICOM_CAND_INFO = 31; # if files in tarchive are not all DICOMs or
                                   # if at least one patient name mismatch
                                   # between the one stored in DICOM files and
                                   # the one stored in mri_upload

# script execution failures
our $DICOMTAR_FAILURE       = 32; # if dicomTar.pl execution failed
our $TARCHIVELOADER_FAILURE = 33; # if tarchiveLoader execution failed

our $CLEANUP_UPLOAD_FAILURE = 34; # if removal/clean up of the uploaded file in
                                  # the incoming folder failed






#### --- FROM dicom-archive/updateMRI_upload.pl

# validation failures
our $TARCHIVE_ALREADY_UPLOADED = 40; # if the tarchive was already uploaded






#### --- FROM uploadNeuroDB/NeuroDB/MRIProcessingUtility.pm

# database related failures
our $TARCHIVE_NOT_IN_DB        = 50; # if tarchive not found in the database
our $GET_PSC_FAILURE           = 51; # if could not determine PSC from the DB
our $GET_SCANNERID_FAILURE     = 52; # if could not determine scannerID from DB
our $CAND_REGISTRATION_FAILURE = 53; # if candidate registration failed


# file related failures
our $EXTRACT_ARCHIVE_FAILURE = 54; # if extraction of the archive failed
our $CORRUPTED_TARCHIVE      = 55; # if mismatch between md5sum stored in the
                                   # tarchive table and the md5sum of the
                                   # tarchive from the file system

# study related failures
our $GET_SUBJECT_ID_FAILURE = 56; # if the getSubjectIDs function from the
                                  # profile does not return subject IDs






#### --- FROM uploadNeuroDB/minc_deletion.pl

# validation failures
our $FILEID_SERIESUID_ARG_FAILURE = 60; # if seriesUID and fileID both provided
                                        # as input to the file (it should always
                                        # be one or the other)






#### --- FROM uploadNeuroDB/minc_insertion.pl

# validation failures
our $INVALID_TARCHIVE   = 70; # if tarchive validation is not set to 1 in the
                              # mri_upload table
our $CANDIDATE_MISMATCH = 71; # if candidate PSCID and CandID do not match
our $FILE_NOT_UNIQUE    = 72; # if (MINC) file is not unique and already
# inserted
our $UNKNOW_PROTOCOL    = 73; # if could not find acquisition protocol of the
# MINC
our $PROTOCOL_NOT_IN_PROFILE = 74; # if the acquisition protocol could be
                                   # determined but is not included in the
                                   # isFileToBeRegisteredGivenProtocol function
                                   # of the profile file






#### --- FROM uploadNeuroDB/tarchiveLoader

# script execution failures
our $TARCHIVE_VALIDATION_FAILURE = 80; # if tarchive_validation.pl failed

# file related failures
our $NO_VALID_MINC_CREATED = 81; # if no valid MINC file was created (non-scout)
our $NO_MINC_INSERTED      = 82; # if no MINC files was inserted (invalid study)

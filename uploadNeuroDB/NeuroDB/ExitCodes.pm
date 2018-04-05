use strict;
use warnings;

package NeuroDB::ExitCodes;

=pod

=head1 NAME

NeuroDB::ExitCodes -- Class regrouping all the exit codes used by the imaging
insertion scripts

=head1 SYNOPSIS

  use NeuroDB::ExitCodes;

  # testing if an argument was given to the script
  if ( !$ARGV[0] ) {
      print $Help;
      print "$Usage\n\tERROR: Missing argument\n\n";
      exit $NeuroDB::ExitCodes::MISSING_ARG;
  }

  # if script ran successfuly, exit with success exit code (a.k.a. 0)
  exit $NeuroDB::ExitCodes::SUCCESS;


=head1 DESCRIPTION

This class lists all the exit codes used by the imaging insertion scripts.

The exit codes are organized per script, together with a section that
represents common failures to most scripts. For each script, exit codes are
organized based on their use (validation failures, database related failures,
file related failures, script execution failures, study related failures,
input error checking and setting failures). Note that not all of the possible
exit codes are used by each script, giving some room to add some later on if
needed.

Below is a list of the possible exit codes organized per script:

1. Common exit codes to most insertion scripts (exit codes from 0 to 19, 0 =
exit script with success status)

2. Exit codes from batch_uploads_imageuploader (exit codes from 20 to 39)

3. Exit codes from batch_uploads_tarchive (no exit codes available yet, exit
codes will be from 40 to 59)

4. Exit codes from dicom-archive/dicomTar.pl (exit codes from 60 to 79)

5. Exit codes from dicom-archive/updateMRI_upload (exit codes from 80 to 99)

6. Exit codes from DTIPrep/DTIPrep_pipeline.pl (exit codes from 100 to 119)

7. Exit codes from DTIPrep/DTIPrepRegister.pl (exit codes from 120 to 139)

8. Exit codes from uploadNeuroDB/imaging_upload_file.pl (exit codes from 140
to 159)

9. Exit codes from uploadNeuroDB/NeuroDB/ImagingUpload.pm (exit codes from 160
to 179)

10. Exit codes from uploadNeuroDB/NeuroDB/MRIProcessingUtility.pm (exit codes
 from 180 to 199)

11. Exit codes from uploadNeuroDB/minc_deletion.pl (exit codes from 200 to 219)

12. Exit codes from uploadNeuroDB/minc_insertion.pl (exit codes from 220 to 239)

13. Exit codes from uploadNeuroDB/register_processed_data.pl (exit codes from
240 to 259)

14. Exit codes from uploadNeuroDB/tarchiveLoader (exit codes from 260 to 279)


=head1 LICENSING

License: GPLv3


=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut




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

# database related failure
# called from minc_insertion.pl & register_processed_data.pl
our $FILE_NOT_UNIQUE = 6; # if file to register is not unique & already
                          # inserted

# other generic failure
our $FILE_OR_FOLDER_DOES_NOT_EXIST = 6; # if file or folder does not exist





#### --- FROM batch_uploads_imageuploader

# validation failures
our $UPLOADED_FILE_TYPE_FAILURE = 20; # if the uploaded file is not a .tgz,
                                      # tar.gz or .zip file
our $PHANTOM_ENTRY_FAILURE      = 21; # if the phantom entry in the text file is
                                      # not 'N' nor 'Y'
our $PNAME_FILENAME_MISMATCH    = 22; # if patient name and beginning of
                                      # uploaded filename do not match
our $PNAME_PHANTOM_MISMATCH     = 23; # if patient name provided in the text
                                      # file but phantom is set to 'Y'






#### --- FROM batch_uploads_tarchive

#TODO: TO BE DONE LATER ON (ERROR CODES WOULD BE BETWEEN 40 & 59)






#### --- FROM dicom-archive/dicomTar.pl

# input error checking and setting failures
our $TARGET_EXISTS_NO_CLOBBER  = 60; # if tarchive already exists but option
                                     # -clobber was not set

# database related failures
our $TARCHIVE_INSERT_FAILURE   = 61; # if insertion in tarchive tables failed

# script execution failures
our $UPDATE_MRI_UPLOAD_FAILURE = 62; # if updateMRI_Upload.pl execution failed






#### --- FROM dicom-archive/updateMRI_upload.pl

# validation failures
our $TARCHIVE_ALREADY_UPLOADED = 80; # if the tarchive was already uploaded






#### --- FROM DTIPrep/DTIPrep_pipeline.pl

# validation failures
our $NO_DTIPREP_VERSION       = 100; # if no DTIPrep version could be found
our $NO_MINCDIFFUSION_VERSION = 101; # if no mincdiffusion version could be
                                     # found
                                    # NOTE: ALSO USED BY DTIPrepRegister.pl
our $NO_NIAK_PATH             = 102; # if no valid NIAK path could be found

# processing exits
our $NO_POST_PROCESSING_TO_RUN = 103; # if no post-processing will be run






#### --- FROM DTIPrep/DTIPrepRegister.pl

# validation failures
our $UNREADABLE_DTIPREP_PROTOCOL = 120; # if DTIPrep XML protocol cannot be
# read
our $GET_OUTPUT_LIST_FAILURE     = 121; # if could not get the list of outputs
                                        # for the DTI file
our $MISSING_PREPROCESSED_FILES  = 122; # if some preprocess files are missing
our $MISSING_POSTPROCESSED_FILES = 123; # if some post-process files are missing
our $NO_TOOL_NAME_VERSION        = 124; # if tool name & version not available





#### --- FROM uploadNeuroDB/imaging_upload_file.pl

# input error checking and setting failures
our $UPLOAD_ID_PATH_MISMATCH = 140; # if upload path given as an argument does
                                    # not match the path stored in the
                                    # mri_upload table for the UploadID given
                                    # as an argument
our $INVALID_DICOM_CAND_INFO = 141; # if files in tarchive are not all DICOMs
                                    # or if at least one patient name mismatch
                                    # between the one stored in DICOM files and
                                    # the one stored in mri_upload

# script execution failures
our $DICOMTAR_FAILURE        = 142; # if dicomTar.pl execution failed
our $TARCHIVELOADER_FAILURE  = 143; # if tarchiveLoader execution failed

our $CLEANUP_UPLOAD_FAILURE  = 144; # if removal/clean up of the uploaded
                                    # file in the incoming folder failed






#### --- FROM uploadNeuroDB/NeuroDB/ImagingUpload.pm

# validation failures
our $DICOM_PNAME_EXTRACTION_FAILURE = 160; # if tarchive was already uploaded






#### --- FROM uploadNeuroDB/NeuroDB/MRIProcessingUtility.pm

# database related failures
our $TARCHIVE_NOT_IN_DB        = 180; # if tarchive not found in the database
our $GET_PSC_FAILURE           = 181; # if could not determine PSC from the DB
our $GET_SCANNERID_FAILURE     = 182; # if could not determine scannerID from DB
our $CAND_REGISTRATION_FAILURE = 183; # if candidate registration failed


# file related failures
our $EXTRACT_ARCHIVE_FAILURE = 184; # if extraction of the archive failed
our $CORRUPTED_TARCHIVE      = 185; # if mismatch between md5sum stored in the
                                    # tarchive table and the md5sum of the
                                    # tarchive from the file system

# study related failures
our $GET_SUBJECT_ID_FAILURE = 186; # if the getSubjectIDs function from the
                                   # profile does not return subject IDs






#### --- FROM uploadNeuroDB/minc_deletion.pl

# validation failures
our $FILEID_SERIESUID_ARG_FAILURE = 200; # if seriesUID and fileID both provided
                                         # as input to the file (it should
                                         # always be one or the other)






#### --- FROM uploadNeuroDB/minc_insertion.pl

# validation failures
our $INVALID_TARCHIVE   = 220; # if tarchive validation is not set to 1 in the
                               # mri_upload table
our $CANDIDATE_MISMATCH = 221; # if candidate PSCID and CandID do not match
our $UNKNOW_PROTOCOL    = 222; # if could not find acquisition protocol of the
                               # MINC
our $PROTOCOL_NOT_IN_PROFILE = 223; # if the acquisition protocol could be
                                    # determined but is not included in the
                                    # isFileToBeRegisteredGivenProtocol function
                                    # of the profile file






#### --- FROM uploadNeuroDB/register_processed_data.pl

# validation failures
our $INVALID_SOURCEFILEID = 240; # if source file ID argument is not valid

# database related failures
our $GET_SESSIONID_FROM_SOURCEFILEID_FAILURE = 241; # if failed to get SessionID
                                                    # from the sourceFileID
our $GET_ACQUISITION_PROTOCOL_ID_FAILURE     = 242; # if failed to determine the
                                                    # acquisition protocol ID
our $FILE_REGISTRATION_FAILURE               = 243; # if file registration
                                                    # into the database failed






#### --- FROM uploadNeuroDB/tarchiveLoader

# script execution failures
our $TARCHIVE_VALIDATION_FAILURE = 260; # if tarchive_validation.pl failed

# file related failures
our $NO_VALID_MINC_CREATED = 261; # if no valid MINC file was created
                                  # (non-localizers)
our $NO_MINC_INSERTED      = 262; # if no MINC files was inserted (invalid
                                  # study)






#### --- FROM uploadNeuroDB/NeuroDB/bin/minc2jiv.pl

our $REGISTER_PROGRAM_FAILURE = 280; # if MNI::Spawn::RegisterPrograms failed

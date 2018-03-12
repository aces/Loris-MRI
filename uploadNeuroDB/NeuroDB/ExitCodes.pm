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
represents common failures to most scripts. (note, not all of the possible
exit codes are used by each script, giving some room to add some later on if
needed). For each script, exit codes are organized based on their use
(validation failures, database related failures, file related failures,
script execution failures, study related failures, input error checking and
setting failures).

Below is a list of the possible exit codes organized per script:

1. Common exit codes to most insertion scripts (exit codes from 0 to 9, 0 =
exit script with success status)

2. Exit codes from batch_uploads_imageuploader (exit codes from 10 to 19)

3. Exit codes from batch_uploads_tarchive (no exit codes available yet, exit
codes will be from 20 to 29)

4. Exit codes from dicom-archive/dicomTar.pl (exit codes from 30 to 39)

5. Exit codes from dicom-archive/updateMRI_upload (exit codes from 40 to 49)

6. Exit codes from DTIPrep/DTIPrep_pipeline.pl (exit codes from 50 to 59)

7. Exit codes from DTIPrep/DTIPrepRegister.pl (exit codes from 60 to 69)

8. Exit codes from uploadNeuroDB/imaging_upload_file.pl (exit codes from 70
to 79)

9. Exit codes from uploadNeuroDB/NeuroDB/ImagingUpload.pm (exit codes from 80
to 89)

10. Exit codes from uploadNeuroDB/NeuroDB/MRIProcessingUtility.pm (exit codes
 from 90 to 99)

11. Exit codes from uploadNeuroDB/minc_deletion.pl (exit codes from 100 to 109)

12. Exit codes from uploadNeuroDB/minc_insertion.pl (exit codes from 110 to 119)

13. Exit codes from uploadNeuroDB/register_processed_data.pl (exit codes from
120 to 129)

14. Exit codes from uploadNeuroDB/tarchiveLoader (exit codes from 130 to 139)


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

#TODO: TO BE DONE LATER ON (ERROR CODES WOULD BE BETWEEN 20 & 29)






#### --- FROM dicom-archive/dicomTar.pl

# input error checking and setting failures
our $TARGET_EXISTS_NO_CLOBBER  = 40; # if tarchive already exists but option
                                     # -clobber was not set

# database related failures
our $TARCHIVE_INSERT_FAILURE   = 41; # if insertion in tarchive tables failed

# script execution failures
our $UPDATE_MRI_UPLOAD_FAILURE = 42; # if updateMRI_Upload.pl execution failed






#### --- FROM dicom-archive/updateMRI_upload.pl

# validation failures
our $TARCHIVE_ALREADY_UPLOADED = 60; # if the tarchive was already uploaded






#### --- FROM DTIPrep/DTIPrep_pipeline.pl

# validation failures
our $NO_DTIPREP_VERSION       = 80; # if no DTIPrep version could be found
our $NO_MINCDIFFUSION_VERSION = 81; # if no mincdiffusion version could be found
                                    # NOTE: ALSO USED BY DTIPrepRegister.pl
our $NO_NIAK_PATH             = 82; # if no valid NIAK path could be found

# processing exits
our $NO_POST_PROCESSING_TO_RUN = 83; # if no post-processing will be run






#### --- FROM DTIPrep/DTIPrepRegister.pl

# validation failures
our $UNREADABLE_DTIPREP_PROTOCOL = 100; # if DTIPrep XML protocol cannot be
# read
our $GET_OUTPUT_LIST_FAILURE     = 101; # if could not get the list of outputs
                                        # for the DTI file
our $MISSING_PREPROCESSED_FILES  = 102; # if some preprocess files are missing
our $MISSING_POSTPROCESSED_FILES = 103; # if some post-process files are missing
our $NO_TOOL_NAME_VERSION        = 104; # if tool name & version not available

# database related failures
our $XML_PROTOCOL_INSERT_FAILURE = 105; # if XML protocol insertion failed
our $XML_QCREPORT_INSERT_FAILURE = 106; # if XML QC report insertion failed
our $TXT_QCREPORT_INSERT_FAILURE = 107; # if text QC report insertion failed






#### --- FROM uploadNeuroDB/imaging_upload_file.pl

# input error checking and setting failures
our $UPLOAD_ID_PATH_MISMATCH = 120; # if upload path given as an argument does
                                    # not match the path stored in the
                                    # mri_upload table for the UploadID given
                                    # as an argument
our $INVALID_DICOM_CAND_INFO = 121; # if files in tarchive are not all DICOMs
                                    # or if at least one patient name mismatch
                                    # between the one stored in DICOM files and
                                    # the one stored in mri_upload

# script execution failures
our $DICOMTAR_FAILURE       = 122; # if dicomTar.pl execution failed
our $TARCHIVELOADER_FAILURE = 123; # if tarchiveLoader execution failed

our $CLEANUP_UPLOAD_FAILURE = 124; # if removal/clean up of the uploaded file in
                                   # the incoming folder failed






#### --- FROM uploadNeuroDB/NeuroDB/ImagingUpload.pm

# validation failures
our $DICOM_PNAME_EXTRACTION_FAILURE = 140; # if tarchive was already uploaded






#### --- FROM uploadNeuroDB/NeuroDB/MRIProcessingUtility.pm

# database related failures
our $TARCHIVE_NOT_IN_DB        = 160; # if tarchive not found in the database
our $GET_PSC_FAILURE           = 161; # if could not determine PSC from the DB
our $GET_SCANNERID_FAILURE     = 162; # if could not determine scannerID from DB
our $CAND_REGISTRATION_FAILURE = 163; # if candidate registration failed


# file related failures
our $EXTRACT_ARCHIVE_FAILURE = 164; # if extraction of the archive failed
our $CORRUPTED_TARCHIVE      = 165; # if mismatch between md5sum stored in the
                                    # tarchive table and the md5sum of the
                                    # tarchive from the file system

# study related failures
our $GET_SUBJECT_ID_FAILURE = 166; # if the getSubjectIDs function from the
                                   # profile does not return subject IDs






#### --- FROM uploadNeuroDB/minc_deletion.pl

# validation failures
our $FILEID_SERIESUID_ARG_FAILURE = 180; # if seriesUID and fileID both provided
                                         # as input to the file (it should
                                         # always be one or the other)






#### --- FROM uploadNeuroDB/minc_insertion.pl

# validation failures
our $INVALID_TARCHIVE   = 200; # if tarchive validation is not set to 1 in the
                               # mri_upload table
our $CANDIDATE_MISMATCH = 201; # if candidate PSCID and CandID do not match
our $UNKNOW_PROTOCOL    = 202; # if could not find acquisition protocol of the
                               # MINC
our $PROTOCOL_NOT_IN_PROFILE = 203; # if the acquisition protocol could be
                                    # determined but is not included in the
                                    # isFileToBeRegisteredGivenProtocol function
                                    # of the profile file






#### --- FROM uploadNeuroDB/register_processed_data.pl

# validation failures
our $INVALID_SOURCEFILEID = 220; # if source file ID argument is not valid

# database related failures
our $GET_SESSIONID_FROM_SOURCEFILEID_FAILURE = 221; # if failed to get SessionID
                                                    # from the sourceFileID
our $GET_ACQUISITION_PROTOCOL_ID_FAILURE     = 222; # if failed to determine the
                                                    # acquisition protocol ID
our $FILE_REGISTRATION_FAILURE               = 223; # if file registration
                                                    # into the database failed






#### --- FROM uploadNeuroDB/tarchiveLoader

# script execution failures
our $TARCHIVE_VALIDATION_FAILURE = 240; # if tarchive_validation.pl failed

# file related failures
our $NO_VALID_MINC_CREATED = 241; # if no valid MINC file was created
                                  # (non-localizers)
our $NO_MINC_INSERTED      = 242; # if no MINC files was inserted (invalid
                                  # study)
our $XLOG_FAILURE          = 243; # if xlog is set, failed to fork a tail to
                                  # the log file

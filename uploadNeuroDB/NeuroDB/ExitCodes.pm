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

Below is a list of the possible exit codes:

##### ---- SECTION 1:  EXIT CODES COMMON TO MOST IMAGING INSERTION SCRIPTS

1. Success: exit code = 0 upon success.

2. Common input error checking and setting failures (exit codes from 1 to 19)

3. Common database related failures (exit codes from 20 to 39)

4. Common configuration failures (exit codes from 40 to 59)

5. Common file manipulation failures (exit codes from 60 to 79)

6. Other common generic failures (exit codes from 80 to 149)


##### ---- SECTION 2: SCRIPT SPECIFIC EXIT CODES NOT COVERED IN SECTION 1

7. Exit codes from C<batch_uploads_imageuploader> (exit codes from 150 to 159)

8. Exit codes from C<DTIPrep/DTIPrepRegister.pl> (exit codes from 160 to 169)

9. Exit codes from C<uploadNeuroDB/NeuroDB/ImagingUpload.pm> (exit codes from
170 to 179)

10. Exit codes from C<uploadNeuroDB/minc_insertion.pl> (exit codes from 180
to 189)

11. Exit codes from C<uploadNeuroDB/tarchiveLoader> (exit codes from 190 to 199)

12. Exit codes from former scripts that have been removed (exit codes from 200
to 210)


=head1 LICENSING

License: GPLv3


=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut




##### ---- SECTION 1:  EXIT CODES COMMON TO MOST IMAGING INSERTION SCRIPTS

## -- Script ran successfully
our $SUCCESS = 0; # yeah!! Success!!


## -- Common input error checking and setting failures (exit codes from 1 to 19)
our $GETOPT_FAILURE       = 1; # if no getOptions were set
our $PROFILE_FAILURE      = 2; # if no profile file specified
our $MISSING_ARG          = 3; # if missing script's argument(s)
our $DB_SETTINGS_FAILURE  = 4; # if DB settings in profile file are not set
our $INVALID_PATH         = 5; # if path to file or folder does not exist
our $INVALID_ARG          = 6; # if one of the program arguments is invalid
our $INVALID_IMPORT       = 7; # if an import statement failed


## -- Common database related failures (exit codes from 20 to 39)
our $FILE_NOT_UNIQUE        = 20; # if file to register is not unique & already
                                  # inserted
our $INSERT_FAILURE         = 21; # if an INSERT query failed
our $CORRUPTED_FILE         = 22; # if mismatch between the file's md5sum and
                                  # the hash stored in the database
our $SELECT_FAILURE         = 23; # if a SELECT query did not return anything
our $UPDATE_FAILURE         = 24; # if an UPDATE query failed
our $BAD_CONFIG_SETTING     = 25; # if bad config setting
our $MISSING_CONFIG_SETTING = 26; # if config setting has not been set in the
                                  # Config module


## -- Common configuration failures (exit codes from 40 to 59)
our $INVALID_ENVIRONMENT_VAR       = 40; # used when an environment variable is
                                         # either missing or has an invalid
                                         # value
our $PROJECT_CUSTOMIZATION_FAILURE = 41; # used when either missing a function
                                         # or a customization variable


## -- Common file manipulation failures (exit codes from 60 to 79)
our $EXTRACTION_FAILURE      = 60; # if archive extraction failed
our $FILE_TYPE_CHECK_FAILURE = 61; # if different file type from what's expected
our $INVALID_DICOM           = 62; # if DICOM is invalid
our $MISSING_FILES           = 63; # if there are missing files compared to
                                   # what is expected
our $UNREADABLE_FILE         = 64; # if could not properly read a file content


## -- Other common generic failures (exit codes from 80 to 149)
our $CLEANUP_FAILURE           = 80; # if cleanup after script execution failed
our $MISSING_TOOL_VERSION      = 81; # if missing the tool version information
our $PROGRAM_EXECUTION_FAILURE = 82; # if script execution failed
our $TARGET_EXISTS_NO_CLOBBER  = 83; # if tarchive already exists but option
                                     # -clobber was not set
our $UNKNOWN_PROTOCOL          = 84; # if could not find acquisition protocol
                                     # of the file to be inserted
our $NOT_A_SINGLE_STUDY        = 85; # if the upload regroups multiple studies
our $GET_SUBJECT_ID_FAILURE    = 86; # if could not determine subject IDs
our $GET_SESSION_ID_FAILURE    = 87; # if could not determine session ID


##### ---- SECTION 2: SCRIPT SPECIFIC EXIT CODES NOT COVERED IN SECTION 1


## -- FROM batch_uploads_imageuploader (exit codes from 150 to 159)

# validation failures
our $PHANTOM_ENTRY_FAILURE   = 150; # if the phantom entry in the text file is
                                    # not 'N' nor 'Y'
our $PNAME_FILENAME_MISMATCH = 151; # if patient name and filename do not match


## -- FROM DTIPrep/DTIPrepRegister.pl (exit codes from 160 to 169)

# validation failures
our $GET_OUTPUT_LIST_FAILURE = 160; # if could not get the list of outputs
                                    # for the DTI file


## -- FROM uploadNeuroDB/NeuroDB/ImagingUpload.pm (exit codes from 170 to 179)

# validation failures
our $DICOM_PNAME_EXTRACTION_FAILURE = 170; # if patient name cannot be
                                           # extracted from the DICOM files


## -- FROM uploadNeuroDB/minc_insertion.pl (exit codes from 180 to 189)

# validation failures
our $INVALID_TARCHIVE   = 180; # if tarchive validation is not set to 1 in the
                               # mri_upload table
our $CANDIDATE_MISMATCH = 181; # if candidate PSCID and CandID do not match


## -- FROM uploadNeuroDB/tarchiveLoader (exit codes from 190 to 199)

# file related failures
our $NO_VALID_MINC_CREATED = 190; # if no valid MINC file was created
                                  # (excluding project-specified acquisitions)


## -- FROM former scripts that have been removed (exit codes from 200 to 210)

our $REGISTER_PROGRAM_FAILURE = 200; # if MNI::Spawn::RegisterPrograms failed

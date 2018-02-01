use strict;
use warnings;

package NeuroDB::ExitCodes;


# input checking and setting failures

my $getopt_failure   = 1;
my $no_profile       = 1;
my $missing_argument = 1;
my $no_db_settings   = 1;


# database related failures

my $no_upload_id            = 1;
my $cand_validation_failure = 1;
my $unknown_protocol        = 1;
my $no_tarchive_in_db       = 1;
my $get_psc_failure         = 1;
my $get_scanner_id_failure  = 1;
my $candidate_registration_failure = 1;

# file related failures

my $file_does_not_exist     = 1;
my $cleanup_dir_failure     = 1;
my $file_already_uploaded   = 1;
my $extract_archive_failure = 1;
my $corrupted_archive       = 1;

# study related failures

my $no_minc_to_insert = 1;
my $invalid_mri_study = 1;
my $get_subject_id_failure = 1;


# script execution failures

my $dicomTar_failure       = 1;
my $tarchiveLoader_failure = 1;
my $tarchive_validation_failure = 1;



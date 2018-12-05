#! /usr/bin/perl

=pod

=head1 NAME

run_defacing.pl -- a script that creates defaced images for anatomical
acquisitions specified in the Config module of LORIS.


=head1 SYNOPSIS

perl tools/run_defacing_script.pl C<[options]>

Available options are:

-profile     : name of the config file in C<../dicom-archive/.loris_mri>
-tarchive_ids: comma-separated list of MySQL TarchiveIDs
-verbose     : be verbose


=head1 DESCRIPTION

This script will create defaced images for anatomical acquisitions that are
specified in the Config module of LORIS.


=head1 LICENSING

License: GPLv3


=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut


use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use File::Path 'make_path';

use NeuroDB::DBI;
use NeuroDB::ExitCodes;

my $profile;
my $session_ids;
my $verbose        = 0;
my $profile_desc   = "Name of the config file in ../dicom-archive/.loris_mri";
my $session_ids_desc = "Comma-separated list of SessionIDs on which to run the "
                       . "defacing algorithm (if not set, will deface images for "
                       . "all SessionIDs present in the database)";

my @opt_table = (
    [ "-profile",    "string",  1, \$profile,     $profile_desc      ],
    [ "-sessionIDs", "string",  1, \$session_ids, $session_ids_desc ],
    [ "-verbose",    "boolean", 1, \$verbose,     "Be verbose"       ]
);

my $Help = <<HELP;
**********************************************************************************
DEFACE ANATOMICAL SCANS BASED ON SCAN TYPES TO DEFACE IN THE CONFIGURATION MODULE
**********************************************************************************

This script will run the defacing algorithm on anatomical scan types listed in the
compute_defaced_images of the imaging pipeline section of the configuration module.

If a list of SessionIDs is provided using the option -sessionIDs, then the defacing
algorithm will be run restricted to MINC files belonging to those SessionIDs.

If -sessionIDs is not set, the defacing algorithm will be run on MINC files
belonging to all SessionIDs present in the database.

Documentation: perldoc run_defacing_script.pl

HELP

my $Usage = <<USAGE;
Usage: $0 [options]
       $0 -help to list options
USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;



## input error checking

if (!$ENV{LORIS_CONFIG}) {
    print STDERR "\n\tERROR: Environment variable 'LORIS_CONFIG' not set\n\n";
    exit $NeuroDB::ExitCodes::INVALID_ENVIRONMENT_VAR;
}

if (!defined $profile || !-e "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
    print $Help;
    print STDERR "$Usage\n\tERROR: You must specify a valid and existing profile.\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }

if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}



## establish database connection

my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\n==> Successfully connected to the database \n" if $verbose;



## get config settings

my $ref_scan_type = &NeuroDB::DBI::getConfigSetting(\$dbh, 'reference_scan_type_for_defacing');
my $to_deface     = &NeuroDB::DBI::getConfigSetting(\$dbh, 'modalities_to_deface'            );
my $data_dir      = &NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath'                 );
$data_dir         =~ s/\/$//;  # remove trailing /
unless ($ref_scan_type && $to_deface) {
    print STDERR "\n==> ERROR: you need to configure both the "
                 . "reference_scan_type_for_defacing & modalities_to_deface config "
                 . "settings in the imaging pipeline section of the Config module.\n"
                 . "If these configurations are not present, make sure you have run "
                 . "all the patches coming with the LORIS release you are using.\n";
    exit $NeuroDB::ExitCodes::SELECT_FAILURE;
}



## get environment variables

my $tmp_dir    = $ENV{'TMPDIR'};
my $mni_models = $ENV{'MNI_MODELS'};
my $beastlib   = $ENV{'BEASTLIB'};
unless ($mni_models && $beastlib && $tmp_dir) {
    print STDERR "\n==> ERROR: the environment variables 'TMPDIR', 'MNI_MODELS' and "
                 . "'BEASTLIB' are required to be set for the defacing script to "
                 . "run. Please make sure you updated your environment file with "
                 . "the proper variables and that you source your environment file "
                 . "before running this script.\n";
    exit $NeuroDB::ExitCodes::INVALID_ENVIRONMENT_VAR;
}



## grep the list of MINC files that will need to be defaced

print "\n==> Fetching all FileIDs to deface.\n" if $verbose;
my @session_ids = defined $session_ids ? split(",", $session_ids) : ();
my %files_hash = grep_FileIDs_to_deface(\@session_ids, $to_deface);



## Loop through SessionIDs
foreach my $session_id (keys %files_hash) {
    # extract the hash of the list of files to deface for that session ID
    my %session_files = %{ $files_hash{$session_id} };

    # grep the CandID and VisitLabel for the dataset
    my ($candID, $visit) = grep_candID_visit_from_SessionID($session_id);

    # grep the t1 file of reference for the defacing (first FileID for t1 scan type)
    my $ref_file = grep_t1_ref_file(\%session_files, $ref_scan_type);

    # determine where the result of the deface command will go
    my ($output_basedir, $output_basename) = determine_output_dir_and_basename(
        $tmp_dir, $candID, $visit, $ref_file, $ref_scan_type
    );

    # run the deface command
    create_the_deface_command($ref_file, \%session_files, $output_basename);
}


exit $NeuroDB::ExitCodes::SUCCESS;


=pod

=head3 grep_FileIDs_to_deface($session_id_arr, $modalities_to_deface_arr)

Queries the database for the list of acquisitions' FileID to be used to run the
defacing algorithm based on the provided list of SessionID and Scan_type to
restrict the search.

INPUTS:
  - $session_id_arr          : array of SessionIDs to use when grepping FileIDs
  - $modalities_to_deface_arr: array of Scan_type to use when grepping FileIDs

RETURNS: hash of matching FileIDs to be used to run the defacing algorithm
         organized in a hash as follows:
            {0123}                      # sessionID key
              {flair}                   # flair scan type key
                {$FileID} = $File_path  # key = FileID; value = MINC file path
              {t1}                      # t1 scan type key
                {$FileID} = $File_path  # key = FileID 1; value = MINC file 1 path
                {$FileID} = $File_path  # key = FileID 2; value = MINC file 2 path
=cut

sub grep_FileIDs_to_deface {
    my ($session_id_arr, $modalities_to_deface_arr) = @_;

    # base query
    my $query = "SELECT  SessionID, FileID, Scan_type, File "
                . "FROM  files f "
                . "JOIN  mri_scan_type mst ON (f.AcquisitionProtocolID = mst.ID)";

    # add where close for the different scan types to deface
    my @where = map { "mst.Scan_type = ?" } @$modalities_to_deface_arr;
    $query   .= sprintf(" WHERE (%s) ", join(" OR ", @where));

    # add where close for the session IDs specified to the script if -sessionIDs was set
    if ($session_id_arr) {
        @where  = map { "f.SessionID = ?" } @$session_id_arr;
        $query .= sprintf(" AND (%s) ", join(" OR ", @where));
    }

    my $sth = $dbh->prepare($query);

    # bind parameters
    my $idx = 0;
    foreach my $scan_type (@$modalities_to_deface_arr) {
        # bind scan type parameters
        $idx++;
        $sth->bind_param($idx, $scan_type);
    }
    if ($session_id_arr) {
        foreach my $session_id (@$session_id_arr) {
            # bind sessionID parameters if -sessionIDs set when running the script
            $idx++;
            $sth->bind_param($idx, $session_id);
        }
    }

    $sth->execute();

    # grep the list of FileIDs on which to run defacing
    my %file_id_hash;
    while (my $row = $sth->fetchrow_hashref){
        my $session_key   = $row->{'SessionID'};
        my $scan_type_key = $row->{'Scan_type'};
        my $file_id_value = $row->{'FileID'};
        my $file_value    = $row->{'File'};
        $file_id_hash{$session_key}{$scan_type_key}{$file_id_value} = $file_value;
    }

    return %file_id_hash
}

sub grep_candID_visit_from_SessionID {
    my ($session_id) = @_;

    my $query  = "SELECT CandID, Visit_label FROM session WHERE ID = ?";
    my $result = $dbh->selectrow_hashref($query, undef, $session_id);

    my $cand_id     = $result->{'CandID'     };
    my $visit_label = $result->{'Visit_label'};

    return $cand_id, $visit_label;
}

sub grep_t1_ref_file {
    my ($session_files, $ref_t1_scan_type) = @_;

    my %t1_files   = %{ $$session_files{$ref_t1_scan_type} };
    my @t1_fileIDs = sort( grep( defined $t1_files{$_}, keys %t1_files ) );
    my $ref_fileID = $t1_fileIDs[0];
    my $ref_file   = $t1_files{$ref_fileID};
    delete $$session_files{$ref_t1_scan_type}{$ref_fileID};

    return $ref_file;
}

sub determine_output_dir_and_basename {
    my ($root_dir, $candID, $visit, $ref_file, $ref_t1_scan_type) = @_;

    # determine output base directory and create it if it does not exist yet
    my $output_basedir  = "$root_dir/$candID/$visit/";
    make_path($output_basedir) unless (-e $output_basedir);

    # determine the output base name for the *_deface_grid_0.mnc output
    my $output_basename = $output_basedir . basename($ref_file);
    $output_basename    =~ s/_${ref_t1_scan_type}_\d\d\d\.mnc//i;

    # return the output base directory and output basename
    return $output_basedir, $output_basename;
}

sub create_the_deface_command {
    my ($ref_file, $session_files, $output_basename) = @_;

    # initialize the command with the t1 reference file
    my $cmd = "deface_minipipe.pl $data_dir/$ref_file ";

    # then add all other files that need to be defaced to the command
    foreach my $scan_type (keys $session_files) {
        my %files = %{ $$session_files{$scan_type} };
        foreach my $fileID (keys %files) {
            my $file_relative_path = $$session_files{$scan_type}{$fileID};
            $cmd .= " $data_dir/$file_relative_path ";
        }
    }

    # then finalize the command with the output basename and additional options
    $cmd .= " $output_basename --keep-real-range --beastlib $beastlib "
        . " --model mni_icbm152_t1_tal_nlin_sym_09c "
        . " --model-dir $mni_models";

    system($cmd);
}
#!/usr/bin/perl -w

=pod

=head1 NAME

batch_run_pipeline_qc_face_script.pl -- Run C<pipeline_qc_deface.pl> in batch mode

=head1 SYNOPSIS

perl batch_run_pipeline_qc_face_script.pl [-profile file] [-out_basedir directory] < list_of_files.txt

Available options are:

-profile: name of config file in ../dicom-archive/.loris_mri (typically called prod)

-out_basedir: path to the output base directory where the jpg will be created

=head1 DESCRIPTION

This script creates the 3D rendering QC images on multiple MINC files.
The list of MINC files to use to generate those 3D JPEG images are provided
through a text file (e.g. C<list_of_files.txt> with one file path per line).

An example of what a C<list_of_files.txt> might contain for 3 files to use to
create a 3D JPEG rendering of a scan to be defaced:
 /data/project/data/assembly/123456/V01/mri/processed/MINC_deface/project_123456_V01_t1w_001_t1w-defaced_001.mnc
 /data/project/data/assembly/123456/V01/mri/processed/MINC_deface/project_123456_V01_t1w_002_t1w-defaced_001.mnc
 /data/project/data/assembly/123456/V01/mri/processed/MINC_deface/project_123456_V01_t2w_001_t2w-defaced_001.mnc


=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut


use strict;
use warnings;
no warnings 'once';
use Getopt::Tabular;
use File::Basename;
use NeuroDB::DBI;
use NeuroDB::ExitCodes;

use NeuroDB::Database;
use NeuroDB::DatabaseException;

use NeuroDB::objectBroker::ObjectBrokerException;
use NeuroDB::objectBroker::ConfigOB;




#############################################################
## Create the GetOpt table
#############################################################

my $profile;
my $out_basedir;

my @opt_table = (
    [ '-profile',     'string', 1, \$profile,     'name of config file in ../dicom-archive/.loris_mri'              ],
    [ '-out_basedir', 'string', 1, \$out_basedir, 'path to the output base directory where the jpg will be created' ] 
);

my $Help = <<HELP;
*******************************************************************************
Run pipeline_qc_face.pl in batch mode
*******************************************************************************

This script creates the 3D rendering QC images on multiple MINC files. 
The list of MINC files to use to generate those 3D JPEG images are provided 
through a text file (e.g. C<list_of_files.txt> with one file path per line.

An example of what a C<list_of_files.txt> might contain for 3 files to use to 
create a 3D JPEG rendering of a scan to be defaced:

 /data/project/data/assembly/123456/V01/mri/processed/MINC_deface/project_123456_V01_t1w_001_t1w-defaced_001.mnc
 /data/project/data/assembly/123456/V01/mri/processed/MINC_deface/project_123456_V01_t1w_002_t1w-defaced_001.mnc
 /data/project/data/assembly/123456/V01/mri/processed/MINC_deface/project_123456_V01_t2w_001_t2w-defaced_001.mnc

Documentation: perldoc batch_run_pipeline_qc_face_script.pl

HELP

my $Usage = <<USAGE;
usage: ./batch_run_pipeline_qc_deface_script.pl -profile prod -out_basedir /PATH/FOR/JPEG < list_of_files.txt 
       $0 -help to list options
USAGE

&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV ) || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;




#################################################################
## Input error checking
#################################################################

if (!$ENV{LORIS_CONFIG}) {
    print STDERR "\n\tERROR: Environment variable 'LORIS_CONFIG' not set\n\n";
    exit $NeuroDB::ExitCodes::INVALID_ENVIRONMENT_VAR; 
}

if ( !defined $profile || !-e "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
    print STDERR $Help;
    print STDERR "$Usage\n\tERROR: You must specify a valid and existing profile.\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}

if (!defined $out_basedir || !-e $out_basedir) {
    print STDERR $Help;
    print STDERR "$Usage\n\tERROR: You must specify a valid and existing out_basedir.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}



# ---------------------------------------------------------------
## Establish database connection and grep the database config
# ---------------------------------------------------------------

# old database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# new Moose database connection
my $db  = NeuroDB::Database->new(
    databaseName => $Settings::db[0],
    userName     => $Settings::db[1],
    password     => $Settings::db[2],
    hostName     => $Settings::db[3]
);
$db->connect();



# ----------------------------------------------------------------
## Get config setting using ConfigOB
# ----------------------------------------------------------------

my $configOB = NeuroDB::objectBroker::ConfigOB->new(db => $db);

my $data_dir  = $configOB->getDataDirPath();
my $mail_user = $configOB->getMailUser();
my $bin_dir   = $configOB->getMriCodePath();
my $is_qsub   = $configOB->getIsQsub();





#################################################################
## Read STDIN into an array listing all SessionIDs
#################################################################

my @files_list = <STDIN>;




#################################################################
## Loop through all files to batch magic
#################################################################

my $counter    = 0;
my $stdoutbase = "$data_dir/batch_output/defaceqcstdout.log"; 
my $stderrbase = "$data_dir/batch_output/defaceqcstderr.log";

foreach my $file_in (@files_list) {
    chomp ($file_in);

    $counter++;
    my $stdout   = $stdoutbase.$counter;
    my $stderr   = $stderrbase.$counter;
    my $file_out = $out_basedir . "/" . basename($file_in, ".mnc") . ".jpg";

    my $command = sprintf(
        "pipeline_qc_face.pl %s %s",
        quotemeta($file_in),
        quotemeta($file_out)
    );

    if ($is_qsub) {
        open QSUB, " | qsub -V -S /bin/sh -e " . quotemeta($stderr) . " -o " . quotemeta($stdout) . " -N process_qc_deface_${counter}";
        print QSUB $command;
        close QSUB;
    } else {
        system($command);
    }
} 


exit $NeuroDB::ExitCodes::SUCCESS;





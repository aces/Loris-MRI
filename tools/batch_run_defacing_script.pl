#!/usr/bin/perl -w

=pod

=head1 NAME

batch_run_defacing_script.pl -- Run the defacing algorithm on multiple session IDs in parallel using QSUB

=head1 SYNOPSIS

perl batch_run_defacing_script.pl [-profile file] < list_of_session_IDs.txt

Available options are:

-profile: name of config file in ../dicom-archive/.loris_mri (typically called prod)

=head1 DESCRIPTION

This script runs the defacing pipeline on multiple sessions. The list of
session IDs are provided through a text file (e.g. C<list_of_session_IDs.txt>
with one sessionID per line).

An example of what a C<list_of_session_IDs.txt> might contain for 3 session IDs
to be defaced:

 123
 124
 125

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut



use strict;
use warnings;
no warnings 'once';
use Getopt::Tabular;
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

my @opt_table = (
    [ '-profile', 'string', 1, \$profile, 'name of config file in ../dicom-archive/.loris_mri' ]
);

my $Help = <<HELP;
*******************************************************************************
Run run_defacing_script.pl in batch mode
*******************************************************************************

This script runs the defacing pipeline on multiple sessions. The list of 
session IDs are provided through a text file (e.g. C<list_of_session_IDs.txt> 
with one sessionID per line).

An example of what a C<list_of_session_IDs.txt> might contain for 3 session IDs
to be defaced:

 123
 124
 125

Documentation: perldoc batch_run_defacing_script.pl

HELP

my $Usage = <<USAGE;
usage: ./batch_run_defacing_script.pl -profile prod < list_of_session_IDs.txt [options]
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



# ----------------------------------------------------------------
## Establish database connection
# ----------------------------------------------------------------

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

my @session_ids_list = <STDIN>;






#################################################################
## Loop through all session IDs to batch magic
#################################################################

my $counter    = 0;
my $stdoutbase = "$data_dir/batch_output/defacingstdout.log"; 
my $stderrbase = "$data_dir/batch_output/defacingstderr.log";

foreach my $session_id (@session_ids_list) {

    $counter++;
    my $stdout = $stdoutbase.$counter;
    my $stderr = $stderrbase.$counter;

    my $command = "run_defacing_script.pl -profile $profile -sessionIDs $session_id";

    if ($is_qsub) {
        open QSUB, " | qsub -V -S /bin/sh -e $stderr -o $stdout -N process_defacing_${counter}";
        print QSUB $command;
        close QSUB;
    } else {
        system($command);
    }
} 


exit $NeuroDB::ExitCodes::SUCCESS;





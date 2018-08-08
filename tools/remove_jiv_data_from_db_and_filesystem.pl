#! /usr/bin/perl


=pod

=head1 NAME

remove_jiv_data_from_db_and_filesystem.pl -- Cleans up the JIV data from the
database tables and the filesystem

=head1 SYNOPSIS

perl remove_jiv_data_from_db_and_filesystem.pl C<[options]>

Available option is:

-profile: name of the config file in ../dicom-archive/.loris_mri

=head1 DESCRIPTION

This script will remove the JIV files from the C<parameter_file> table and
move them to the C<$data_dir/archive/bkp_jiv_produced_before_LORIS_20.0> directory of the filesystem for
projects that wish to clean up the JIV data produced in the past. Note that
from release 20.0, JIV datasets will not be produced anymore by the imaging
insertion scripts.

=head2 Methods

=cut

use strict;
use warnings;

use Getopt::Tabular;
use File::Copy;

use NeuroDB::DBI;
use NeuroDB::ExitCodes;



my $profile;
my $profile_desc = "name of config file in ../dicom-archive/.loris_mri";

my @opt_table = (
    [ "-profile", "string", 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"
    ]
);

my $Help = <<HELP;

This script will remove entries in the parameter_file table for the JIV files
 and backup the JIV directory in /data/project/data to the archive folder.

Documentation: perldoc remove_jiv_data_from_db_and_filesystem.pl

HELP

my $Usage = <<USAGE;

Usage: $0 -help to list options

USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;




## Input option error checking
if ( !$profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
        . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}




## establish database connection
my $dbh  = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\n==> Successfully connected to database \n";




## select the JIV parameter type ID from parameter_type
my $query = "SELECT ParameterTypeID FROM parameter_type WHERE Name='jiv_path'";
my $sth   = $dbh->prepare($query);
$sth->execute();

my $row = $sth->fetchrow_hashref();
if ( !$row ) {
    print "\n==> Did not find any entry in the parameter_type table with "
          . "Name='jiv_path'. Exiting now.\n";
    exit $NeuroDB::ExitCodes::SUCCESS;
}
my $param_type_id = $row->{'ParameterTypeID'};




## check to see if there are entries in the parameter_file table
$query = "SELECT * FROM parameter_file WHERE ParameterTypeID=?";
$sth   = $dbh->prepare($query);
$sth->execute($param_type_id);
$row        = $sth->fetchrow_hashref();
my $message = "\n==> Did not find any JIV entries in table parameter_file.\n";
print $message if ( !$row );

# delete entries from parameter_file
my $delete     = "DELETE FROM parameter_file WHERE ParameterTypeID=?";
my $delete_sth = $dbh->prepare($delete);
$delete_sth->execute($param_type_id);

# check to make sure entries have been deleted
$sth->execute($param_type_id);
$row     = $sth->fetchrow_hashref();
if ( !$row ) {
    print "\n==> Succesfully deleted all JIV entries in parameter_file.\n";
    $delete = "DELETE FROM parameter_type WHERE ParameterTypeID=?";
    $delete_sth = $dbh->prepare($delete);
    $delete_sth->execute($param_type_id);
} else {
    print "\n==> Could not delete all JIV entries in parameter_file.\n";
    exit;
}




## backup the JIV directory to the archive directory on the filesystem
# grep the data_dir from the Configuration module of LORIS
my $data_dir = &NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath');
$data_dir    =~ s/\/$//;
my $jiv_dir  = $data_dir . "/jiv";
my $jiv_bkp  = $data_dir . "/archive/bkp_jiv_produced_before_LORIS_20.0";
if (-d $jiv_dir) {
    move($jiv_dir, $jiv_bkp) or die "Cannot move $jiv_dir to $jiv_bkp: $!\n";
    print "\n==> Successfully backed up the jiv directory to $jiv_bkp.\n";   
}



exit $NeuroDB::ExitCodes::SUCCESS;

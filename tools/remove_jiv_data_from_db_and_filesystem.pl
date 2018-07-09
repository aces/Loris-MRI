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

This script will remove the JIV files from the parameter_file table and the
filesystem for projects that wish to clean up and remove completely the JIV
data produced in the past. From now on, JIV datasets will not be produced
anymore.

=head2 Methods

=cut

use strict;
use warnings;

use Getopt::Tabular;
use File::Path qw(remove_tree);

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
 and remove the JIV directory in data_dir.

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
    print "\n==> did not find any entry in the parameter_type table with "
          . "Name='jiv_path'. Exiting now.\n";
    exit $NeuroDB::ExitCodes::SUCCESS;
}
my $param_type_id = $row->{'ParameterTypeID'};




## check to see if there are entries in the parameter_file table
$query = "SELECT * FROM parameter_file WHERE ParameterTypeID=?";
$sth   = $dbh->prepare($query);
$sth->execute($param_type_id);
$row        = $sth->fetchrow_hashref();
my $message = "\n==> did not find any JIV entries in table parameter_file.\n";
print $message if ( !$row );

# delete entries from parameter_file
my $delete     = "DELETE FROM parameter_file WHERE ParameterTypeID=?";
my $delete_sth = $dbh->prepare($delete);
$delete_sth->execute($param_type_id);

# check to make sure entries have been deleted
$sth->execute($param_type_id);
$row     = $sth->fetchrow_hashref();
if ( !$row ) {
    print "\n==> succesfully deleted all JIV entries in parameter_file.\n";
    $delete = "DELETE FROM parameter_type WHERE ParameterTypeID=?";
    $delete_sth = $dbh->prepare($delete);
    $delete_sth->execute($param_type_id);
} else {
    print "\n==> could not delete all JIV entries in parameter_file.\n";
    exit;
}




## delete the JIV directory from the filesystem
# grep the data_dir from the Configuration module of LORIS
my $data_dir = &NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath');
$data_dir    =~ s/\/$//;
my $jiv_dir  = $data_dir . "/jiv";
remove_tree($jiv_dir) if (-d $jiv_dir);





exit $NeuroDB::ExitCodes::SUCCESS;
#!/usr/bin/perl -w
use strict;
use warnings;
no warnings 'once';
use Getopt::Tabular;
use NeuroDB::DBI;
use NeuroDB::ExitCodes;

my $profile   = '';

my @opt_table           = (
    [ "Basic options", "section" ],
    [
        "-profile", "string", 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"
    ]
);

my $Help = <<HELP;
******************************************************************************
Populate the Config table in the database with entries from the $profile file
******************************************************************************

This script needs to be run once during the upgrade to LORIS-MRI v17.1. Its purpose
is to remove some variables defined in the $profile file to the Configuration module
within LORIS. This script assumes that the LORIS upgrade patch has been run, with 
table entries created and set to default values. This script will then update those
values with those that already exist in the $profile file. If the table entry does not
exist in the $profile, it will be kept at the default value of a new install.

HELP
my $Usage = <<USAGE;
usage: tools/ProdToConfig.pl -profile $profile
       $0 -help to list options
USAGE
&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

################################################################
################ Get config setting#############################
################################################################
if (!$profile ) {
    print $Help;
    print "\n$Usage\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( $profile && !@Settings::db ) {
    print "\n\tERROR: You don't have a
    configuration file named '$profile' in:
    $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}


################################################################
################ Establish database connection #################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

my @config_name_arr = ("dataDirBasepath", "prefix", "mail_user", "get_dicom_info",
                       "horizontalPics", "no_nii", "converter", "tarchiveLibraryDir",
                       "lookupCenterNameUsing", "if_sge", "if_site", "DTI_volumes",
                       "t1_scan_type", "reject_thresh", "niak_path", "QCed2_step");

my $data_dir = $Settings::data_dir;
my $prefix = $Settings::prefix;
my $mail_user = $Settings::mail_user;
my $get_dicom_info = $Settings::get_dicom_info;
my $horizontalPics = $Settings::horizontalPics;
my $no_nii = $Settings::no_nii;
my $converter = $Settings::converter;
my $tarchiveLibraryDir = $Settings::tarchiveLibraryDir;
my $lookupCenterNameUsing = $Settings::lookupCenterNameUsing;
my $if_sge;
# Some projects may have manually changed the name of if_sge to is_qsub
# so account for this case here
if (defined($Settings::if_sge)) {
    $if_sge = $Settings::if_sge;
}
if (defined($Settings::is_qsub)) {
    $if_sge = $Settings::is_qsub;
}
my $if_site = $Settings::if_site;
my $DTI_volumes = $Settings::DTI_volumes;
my $t1_scan_type = $Settings::t1_scan_type;
my $reject_thresh = $Settings::reject_thresh;
my $niak_path = $Settings::niak_path;
my $QCed2_step = $Settings::QCed2_step;

my @config_value_arr = ($data_dir, $prefix, $mail_user, $get_dicom_info,
                       $horizontalPics, $no_nii, $converter, $tarchiveLibraryDir,
                       $lookupCenterNameUsing, $if_sge, $if_site, $DTI_volumes,
                       $t1_scan_type, $reject_thresh, $niak_path, $QCed2_step);


my ($config_name, $config_value);
    ## Populate the mri_upload table with necessary entries and get an upload_id 
for my $index (0 .. $#config_name_arr) {
    $config_name = $config_name_arr[$index];
    ## This value was called if_sge in the default profileTemplate, but should be called is_qsub
    if ($config_name eq "if_sge" ) {
        $config_name = "is_qsub";
    }
    $config_value = $config_value_arr[$index];
    updateConfigFromProd(\$dbh, $config_name, $config_value);
}

################################################################
############### insertIntoMRIUpload ############################
################################################################
=pod
updateConfigFromProd()
Description:
  - Update the default values in the Config table to what is inside 
    the $profile file

Arguments:
  $config_name: Variable to set in the Config table
  $config_value : value to set in the Config table

=cut


sub updateConfigFromProd {

    my ( $dbhr, $config_name, $config_value ) = @_;

    my $query_update = "UPDATE Config SET Value=? ";
    my $where = "WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name=?)";
    $query_update = $query_update . $where;

    my $query_select = "SELECT Value FROM Config ";
    $query_select = $query_select . $where;

    # If value is found in the existing prod file, use it to update the database
    if (defined($config_value)) {
        my $config_update = $dbh->prepare($query_update);
        $config_update->execute($config_value,$config_name);
        print "Just updated the Configuration Setting value for " . $config_name . " to become " . $config_value . "\n";
    }
    # Otherwise, keep the default value that is equivalent to a fresh Loris-MRI install
    else {
        my $config_select = $dbh->prepare($query_select);
        $config_select->execute($config_name);
        my $config_default = $config_select->fetchrow_array;
        print "*** WARNING *** " . 
              "The Configuration Setting value for " . $config_name . " is kept at its default value of " . $config_default .
              " because " . $config_name . " is not found in the " . $profile . " file \n";
    }
}

exit $NeuroDB::ExitCodes::SUCCESS;


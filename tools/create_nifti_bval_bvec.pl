#! /usr/bin/perl

=pod

=head1 NAME

create_nifti_bval_bvec.pl -- a script that creates the missing bval and bvec
files for DWI NIfTI acquisitions.


=head1 SYNOPSIS

perl tools/create_nifti_bval_bvec.pl C<[options]>

Available options are:

-profile: name of the config file in C<../dicom-archive/.loris_mri>
-verbose: be verbose


=head1 DESCRIPTION

This script will create the missing NIfTI bval and bvec files for DWI
acquisitions.


=head1 LICENSING

License: GPLv3


=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut



use strict;
use warnings;
use Getopt::Tabular;

use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::ExitCodes;




### Set up Getopt::Tabular

my $profile;
my $verbose      = 0;
my $profile_desc = "Name of the config file in ../dicom-archive/.loris_mri";

my @opt_table = (
    [ "-profile", "string",  1, \$profile, $profile_desc ],
    [ "-verbose", "boolean", 1, \$verbose, "Be verbose"  ]
);

my $Help = <<HELP;
******************************************************************************
CREATE NIFTI BVAL BVEC DWI FILES
******************************************************************************

This will check if the configuration flag for NIfTI files creation is set to
'yes' and will create .bvec and .bval files for the DWI acquisitions that
need to accompany the NIfTI DWI files (bug in mnc2nii that do not create
those files so we create them ourselves based on values present in the MINC
header for acquisition:bvalues, acquisition:direction_x,
acquisition:direction_y and acquisition:direction_z).

Documentation: perldoc create_nifti_bval_bvec.pl

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

my $data_dir   = NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath');
my $create_nii = NeuroDB::DBI::getConfigSetting(\$dbh, 'create_nii');



## exit if create_nii is set to No

unless ($create_nii) {
    print "\nConfig option 'create_nii' set to no. bvec/bval files will not be "
          . "created as NIfTI files are not created by the imaging pipeline\n\n";
    exit $NeuroDB::ExitCodes::SUCCESS;
}



## grep all FileIDs for which acquisition:bvalues are set

print "\n==> Fetching all FileIDs with acquisition:bvalues. \n" if $verbose;

( my $query = <<QUERY ) =~ s/\n/ /g;
  SELECT
    FileID
  FROM
    parameter_file
    JOIN parameter_type USING (ParameterTypeID)
  WHERE
    parameter_type.Name=?
QUERY

my $sth = $dbh->prepare($query);
$sth->execute('acquisition:bvalues');

my @file_ids = map { $_->{'FileID'} }  @{ $sth->fetchall_arrayref( {} ) };

unless (@file_ids) {
    print "\n No files were found with header 'acquisition:bvalues' so no need "
          . "to create bval/bvec files \n";
    exit $NeuroDB::ExitCodes::SUCCESS;
}



## loop through all FileIDs and create bvec/bval files
foreach my $file_id (@file_ids) {

    # load the file based on the FileID
    my $file = NeuroDB::File->new(\$dbh);
    $file->loadFile($file_id);

    # determine paths for bval/bvec files
    my $minc = $file->getFileDatum('File');
    my ($bval_file, $bvec_file) = ($minc) x 2;
    $bval_file =~ s/mnc$/bval/;
    $bvec_file =~ s/mnc$/bvec/;

    # create complementary nifti files for DWI acquisitions
    my $bval_success = NeuroDB::MRI::create_dwi_nifti_bval_file(
        \$file, "$data_dir/$bval_file"
    );
    my $bvec_success = NeuroDB::MRI::create_dwi_nifti_bvec_file(
        \$file, "$data_dir/$bvec_file"
    );

    # check if bval/bvec created & update parameter_file table with their paths
    if ($bval_success) {
        print "\n==> Successfully created bval file for $minc \n";
        # update parameter_file table with bval path
        $file->setParameter('check_bval_filename', $bval_file);
    }
    if ($bvec_success) {
        print "\n==> Successfully created bvec file for $minc \n";
        # update parameter_file table with bvec path
        $file->setParameter('check_bvec_filename', $bvec_file);
    }

}



## disconnect from the database and exit the script with SUCCESS exit code
$dbh->disconnect();
exit $NeuroDB::ExitCodes::SUCCESS;

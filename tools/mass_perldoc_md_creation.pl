#!/usr/bin/perl -w

=pod

=head1 NAME

mass_perldoc_md_creation.pl -- Script to mass produce the C<.md> files
derived from the documentation of the perl scripts and libraries.

=head1 SYNOPSIS

perl mass_perldoc_md_creation.pl C<[options]>

Available options are:

-profile: name of the config file in C<../dicom-archive/.loris_mri>

-verbose: be verbose (boolean)


=head1 DESCRIPTION

This script will need to be run once per release to make sure the C<.md> files
derived from the documentation of the perl scripts and libraries are updated.

If any new script have been added to a given release, make sure to include it
in the variable called C<@script_list> at the beginning of the script.

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut


use strict;
use warnings;

use File::Basename;
use Getopt::Tabular;


use NeuroDB::DBI;
use NeuroDB::ExitCodes;

my @script_list = (
    'DTIPrep/DTI/DTI.pm',
    'DTIPrep/DTIPrepRegister.pl',
    'DTIPrep/DTIPrep_pipeline.pl',
    'batch_uploads_imageuploader',
    'batch_uploads_tarchive',
    'dicom-archive/DICOM/DCMSUM.pm',
    'dicom-archive/DICOM/DICOM.pm',
    'dicom-archive/DICOM/Element.pm',
    'dicom-archive/DICOM/Fields.pm',
    'dicom-archive/DICOM/Private.pm',
    'dicom-archive/DICOM/VRfields.pm',
    'dicom-archive/dicomSummary.pl',
    'dicom-archive/dicomTar.pl',
    'dicom-archive/get_dicom_info.pl',
    'dicom-archive/updateMRI_Upload.pl',
    'tools/BackPopulateSNRAndAcquisitionOrder.pl',
    'tools/create_nifti_bval_bvec.pl',
    'tools/cleanupTarchives.pl',
    'tools/cleanup_paths_of_violation_tables.pl',
    'tools/MakeArchiveLocationRelative.pl',
    'tools/ProdToConfig.pl',
    'tools/database_files_update.pl',
    'tools/dicomDescribe.pl',
    'tools/get_dicom_files.pl',
    'tools/MakeArchiveLocationRelative.pl',
    'tools/mass_perldoc_md_creation.pl',
    'tools/ProdToConfig.pl',
    'tools/remove_jiv_data_from_db_and_filesystem.pl',
    'tools/seriesuid2fileid',
    'tools/splitMergedSeries.pl',
    'tools/updateHeadersBatch.pl',
    'tools/updateHeaders.pl',
    'uploadNeuroDB/NeuroDB/DBI.pm',
    'uploadNeuroDB/NeuroDB/ExitCodes.pm',
    'uploadNeuroDB/NeuroDB/File.pm',
    'uploadNeuroDB/NeuroDB/FileDecompress.pm',
    'uploadNeuroDB/NeuroDB/ImagingUpload.pm',
    'uploadNeuroDB/NeuroDB/MRI.pm',
    'uploadNeuroDB/NeuroDB/MRIProcessingUtility.pm',
    'uploadNeuroDB/NeuroDB/Notify.pm',
    'uploadNeuroDB/bin/concat_mri.pl',
    'uploadNeuroDB/bin/mincpik',
    'uploadNeuroDB/imaging_non_minc_insertion.pl',
    'uploadNeuroDB/imaging_upload_file.pl',
    'uploadNeuroDB/imaging_upload_file_cronjob.pl',
    'uploadNeuroDB/mass_nii.pl',
    'uploadNeuroDB/mass_pic.pl',
    'uploadNeuroDB/minc_deletion.pl',
    'uploadNeuroDB/minc_insertion.pl',
    'uploadNeuroDB/register_processed_data.pl',
    'uploadNeuroDB/tarchiveLoader',
    'uploadNeuroDB/tarchive_validation.pl'
);


my $profile;
my $verbose = 0;

my $profile_desc = "name of config file in ../dicom-archive/.loris_mri";

my @opt_table = (
    [ "-profile", "string",  1, \$profile, $profile_desc ],
    [ "-verbose", "boolean", 1, \$verbose, "Be verbose." ]
);

my $Help = <<HELP;
******************************************************************************
Creates the perldoc .md files stored in LORIS-MRI/docs/scripts_md/
******************************************************************************

This script will need to be run once per release to make sure the .md files
derived from the documentation of the perl scripts and libraries are updated.
If any new script have been added to a given release, make sure to include it
in the variable called \@script_list at the beginning of the script.

Documentation: perldoc mass_perldoc_md_creation.pl

HELP
my $Usage = <<USAGE;
usage: perl tools/mass_perldoc_md_creation.pl -profile \$profile
       $0 -help to list options
USAGE
&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;



## input error checking
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



## database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\n==> Successfully connected to database \n" if $verbose;



## get data directory from the Config table
my $loris_mri_path = NeuroDB::DBI::getConfigSetting(\$dbh, 'MRICodePath');
$loris_mri_path    =~ s/\/$//;



## add the LORIS-MRI directory path to the list of scripts
@script_list = map { $loris_mri_path . '/' . $_ } @script_list;



## create the list of md file based on @script_list and change extension to .md
my $md_path  = $loris_mri_path . '/docs/scripts_md/';
my @suffixes = (".pl", ".pm");
my @md_list  = map { $md_path . basename($_, @suffixes) . ".md"} @script_list;



## loop through script array and create the .md files using pod2markdown
my $git_add = "git add";
for my $index (0 .. $#script_list) {
    my $script  = $script_list[$index];
    my $md_file = $md_list[$index];
    my $command =  "pod2markdown $script $md_file";
    print $command . "\n" if $verbose;
    system($command);
    $git_add .= ' ' . $md_file . ' ';

}

my $message = "\n\tMD files created! \n\tTo add them to git, run the following "
              . "command in the terminal: \n\n";
print $message . $git_add . "\n";


exit $NeuroDB::ExitCodes::SUCCESS;

#! /usr/bin/perl

=pod

=head1 NAME

MRIProtocolRerunner.pl -- Reruns MRI protocol checks on all existing MINC insertions

=head1 SYNOPSIS

Work in progress...

=cut


use strict;
use warnings;
use Getopt::Tabular;
use FindBin;
use File::Temp qw/ tempdir /;


use lib "$FindBin::Bin";
use NeuroDB::File;
use NeuroDB::DBI;
use NeuroDB::MRIProcessingUtility;

my $profile = undef;
my $verbose = 0;

my @opt_table           = (
    [
        "-profile", "string", 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"
    ],
    ["-verbose", "boolean", 1,   \$verbose, "Be verbose."],
);


my $Help = <<HELP;
******************************************************************************
Dicom Validator
******************************************************************************

Author  :
Date    :
Version :

The program does the following

- Gets the location of the uploaded file (.zip,.tar.gz or .tgz)

- Unzips the uploaded file

- Uses the ImagingUpload class to :

   1) Validate the uploaded file (set the validation to true)
   2) Run dicomTar.pl on the file (set the dicomTar to true)
   3) Run tarchiveLoader on the file (set the minc-created to true)
   4) Remove the uploaded file once the previous steps have completed
   5) Update the mri_upload table

Documentation: perldoc imaging_upload_file.pl

HELP
my $Usage = <<USAGE;
usage: $0 </path/to/UploadedFile> -upload_id [options]
       $0 -help to list options
Note:  Please make sure that the </path/to/UploadedFile> and the upload_id
provided correspond to the same upload entry.
USAGE

&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

################################################################
############### Establish database connection ##################
################################################################
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

################################################################
################## Instantiate MRIProcessingUtility ############
################################################################
my $data_dir = NeuroDB::DBI::getConfigSetting(
    \$dbh,'dataDirBasepath'
);

my $template         = "ProtocolCheck-XXXX"; # for tempdir
my $TmpDir = tempdir(
    $template, TMPDIR => 1, CLEANUP => 1
);

my @temp     = split(/\//, $TmpDir);
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs";
if (!-d $LogDir) {
    mkdir($LogDir, 0770);
}
my $logfile  = "$LogDir/$templog.log";
open LOG, ">$logfile";
LOG->autoflush(1);
&logHeader();

my $debug = 0;
my $utility = NeuroDB::MRIProcessingUtility->new(
                  \$dbh,$debug,$TmpDir,$logfile,
                  $LogDir,$verbose
              );

################################################################
############### Get list of files which passed #################
############### protocol checks ################################
################################################################
my $query = 'SELECT FileID, ArchiveLocation, ScannerID, File FROM files f
JOIN tarchive t ON f.TarchiveSource=t.TarchiveID';

my $sth = $dbh->prepare($query);
$sth->execute();

my @failures = ();

while (my @f = $sth->fetchrow_array()) {
    my ($fileID, $archiveLocation, $scannerID, $minc) = @f;

    my $file = NeuroDB::File->new(\$dbh);

    $file->loadFile($fileID);

    my %tarchiveInfo = $utility->createTarchiveArray(
        $archiveLocation, 1
    );

    my $subjectIDsref = $utility->determineSubjectID(
        $scannerID,\%tarchiveInfo,0
    );

    my ($centerName, $centerID) = $utility->determinePSC(\%tarchiveInfo,0);

    my $acquisitionProtocol = undef;
    my $bypass_extra_file_checks = 0;

    ($acquisitionProtocol)
        = $utility->getAcquisitionProtocol(
        $file,
        $subjectIDsref,
        \%tarchiveInfo,
        $centerName,
        $minc,
        $acquisitionProtocol,
        $bypass_extra_file_checks
    );
    if ($acquisitionProtocol =~ /unknown/) {
        push(@failures, $minc);
        print "F: $minc , P: $acquisitionProtocol \n";
    } else {
        print "protocol: $acquisitionProtocol \n center: $centerName \n";
    }
}

print join("\n", @failures);
=pod

=head3 logHeader()

Function that adds a header with relevant information to the log file.

=cut

sub logHeader () {
    print LOG "
    ----------------------------------------------------------------
            AUTOMATED DICOM DATA UPLOAD
    ----------------------------------------------------------------
    *** Date and time of upload    :
    *** Location of source data    :
    *** tmp dir location           :
    ";
}
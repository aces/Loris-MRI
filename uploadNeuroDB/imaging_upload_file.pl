#! /usr/bin/perl

=pod

=head1 NAME

imaging_upload_file.pl -- a single step script for the imaging pre-processing
and insertion pipeline sequence

=head1 SYNOPSIS

perl imaging_upload_file.pl </path/to/UploadedFile> C<[options]>

Available options are:

-profile      : name of the config file in C<../dicom-archive/.loris_mri>

-upload_id    : The Upload ID of the given scan uploaded

-verbose      : if set, be verbose


=head1 DESCRIPTION

The program does the following:

- Gets the location of the uploaded file (.zip, .tar.gz or .tgz)

- Unzips the uploaded file

- Uses the C<ImagingUpload> class to:
   1) Validate the uploaded file   (set the validation to true)
   2) Run C<dicomTar.pl> on the file  (set the C<dicomTar> to true)
   3) Run C<tarchiveLoader> on the file (set the minc-created to true)
   4) Remove the uploaded file once the previous steps have completed
   5) Update the C<mri_upload> table

=head2 Methods

=cut

use strict;
use warnings;
use Carp;
use Getopt::Tabular;
use FileHandle;
use File::Temp qw/ tempdir /;
use File::Basename;
use Data::Dumper;
use FindBin;
use Cwd qw/ abs_path /;

################################################################
# These are the NeuroDB modules to be used #####################
################################################################
use lib "$FindBin::Bin";

use NeuroDB::FileDecompress;
use NeuroDB::DBI;
use NeuroDB::ImagingUpload;
use NeuroDB::Notify;
use NeuroDB::ExitCodes;

my $versionInfo = sprintf "%d revision %2d",
  q$Revision: 1.24 $ =~ /: (\d+)\.(\d+)/;
my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
  localtime(time);
my $date    = sprintf(
                "%4d-%02d-%02d %02d:%02d:%02d",
                $year + 1900,
                $mon + 1, $mday, $hour, $min, $sec
              );
my $profile = undef;    # this should never be set unless you are in a
                        # stable production environment
my $upload_id = undef;  # The uploadID
my $template  = "ImagingUpload-$hour-$min-XXXXXX";    # for tempdir
my $TmpDir_decompressed_folder =
     tempdir( $template, TMPDIR => 1, CLEANUP => 1 );
my $output              = undef;
my $uploaded_file       = undef;
my $message             = '';
my $verbose             = 0;
                        # default for now, run with -verbose option to re-enable
my $notify_detailed     = 'Y';
                        # notification_spool message flag for messages to be
                        # displayed with DETAILED OPTION in the front-end/
                        # imaging_uploader
my $notify_notsummary   = 'N';
                        # notification_spool message flag for messages to be
				       	# displayed with SUMMARY Option in the front-end/
                        # imaging_uploader
my @opt_table           = (
    [ "Basic options", "section" ],
    [
        "-profile", "string", 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"
    ],
    [
        "-upload_id", "string", 1, \$upload_id,
        "The uploadID of the given scan uploaded"
    ],
    ["-verbose", "boolean", 1,   \$verbose, "Be verbose."],
    [ "Advanced options", "section" ],
    [ "Fancy options", "section" ]
);

my $Help = <<HELP;
******************************************************************************
Dicom Validator 
******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo

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
############### input option error checking ####################
################################################################


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
if ( !$ARGV[0] ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: Missing path to the uploaded file "
                 . "argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}

if ( !$upload_id ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: Missing -upload_id argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}

$uploaded_file = abs_path( $ARGV[0] );
unless ( -e $uploaded_file ) {
    print STDERR "\nERROR: Could not find the uploaded file $uploaded_file.\n"
                 . "Please, make sure the path to the uploaded file is "
                 . "valid.\n\n" ;
    exit $NeuroDB::ExitCodes::INVALID_PATH;
}

################################################################
################ Establish database connection #################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

################################################################
####Check that UploadID and path to the file are consistent#####
####i.e. they refer to the same entry in the mri_upload table###
################################################################
my $expected_file = getFilePathUsingUploadID($upload_id);

if ( basename($expected_file) ne basename($uploaded_file)) {
    print STDERR "$Usage\nERROR: The specified upload_id $upload_id does not "
                 . "correspond to the provided file path $uploaded_file.\n\n";
    exit $NeuroDB::ExitCodes::INVALID_ARG;
}

my $file_decompress = NeuroDB::FileDecompress->new($uploaded_file);

################################################################
############### Decompress File ################################
################################################################
################################################################
my $result = $file_decompress->Extract( 
                $TmpDir_decompressed_folder 
             );

################################################################
############### Get Patient_name using UploadID#################
################################################################
################################################################
my $pname = getPnameUsingUploadID($upload_id);

################################################################
################ ImagingUpload  Object #########################
################################################################
my $imaging_upload =
  NeuroDB::ImagingUpload->new( \$dbh, 
                               $TmpDir_decompressed_folder, 
                               $upload_id,
                               $pname, 
                               $profile,
                               $verbose 
                             );

################################################################
############Add the decompressed-folder location in the#########
############mri-upload table####################################
################################################################
$imaging_upload->updateMRIUploadTable(
	'DecompressedLocation',$TmpDir_decompressed_folder,
);
################################################################
################ Instantiate the Notify Class###################
################################################################
my $Notify = NeuroDB::Notify->new(
                  \$dbh
         );

################################################################
########## Validate Candidate Info/File ########################
################################################################

my $is_candinfovalid = $imaging_upload->IsCandidateInfoValid();
if ( !($is_candinfovalid) ) {
    $imaging_upload->updateMRIUploadTable(
	'Inserting', 0);
    $message = "\nThe candidate info validation has failed.\n";
    spool($message,'Y', $notify_notsummary);
    print STDERR $message;
    exit $NeuroDB::ExitCodes::INVALID_DICOM;
}

$message = "\nThe candidate info validation has passed.\n";
spool($message,'N', $notify_notsummary);

################################################################
############### Run DicomTar  ##################################
################################################################
$output = $imaging_upload->runDicomTar();
if ( !$output ) {
    $imaging_upload->updateMRIUploadTable(
	'Inserting', 0);
    $message = "\nThe dicomTar.pl execution has failed.\n";
    spool($message,'Y', $notify_notsummary);
    print STDERR $message;
    exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
}
$message = "\nThe dicomTar.pl execution has successfully completed\n";
spool($message,'N', $notify_notsummary);

################################################################
############### Run runTarchiveLoader###########################
################################################################
$output = $imaging_upload->runTarchiveLoader();
$imaging_upload->updateMRIUploadTable('Inserting', 0);
if ( !$output ) {
    $message = "\nThe tarchiveLoader insertion script has failed.\n";
    spool($message,'Y', $notify_notsummary); 
    print STDERR $message;
    exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
}

################################################################
### If we got this far, dicomTar and tarchiveLoader completed###
#### Remove the uploaded file from the incoming directory#######
################################################################
my $isCleaned = $imaging_upload->CleanUpDataIncomingDir($uploaded_file);
if ( !$isCleaned ) {
    $message = "\nThe uploaded file " . $uploaded_file . " was not removed\n";
    spool($message,'Y', $notify_notsummary);
    print STDERR $message;
    exit $NeuroDB::ExitCodes::CLEANUP_FAILURE;
}
$message = "\nThe uploaded file " . $uploaded_file . " has been removed\n\n";
spool($message,'N', $notify_notsummary);

################################################################
############### Spool last completion message ##################
################################################################
my ($minc_created, $minc_inserted) = getNumberOfMincFiles($upload_id);

$message = "\nThe insertion scripts have completed "
            . "with $minc_created minc file(s) created, "
            . "and $minc_inserted minc file(s) "
            . "inserted into the database \n";
spool($message,'N', $notify_notsummary);

################################################################
############### getPnameUsingUploadID###########################
################################################################
=pod

=head3 getPnameUsingUploadID($upload_id)

Function that gets the patient name using the upload ID

INPUT: The upload ID

RETURNS: The patient name

=cut


sub getPnameUsingUploadID {

    my $upload_id = shift;
    my ( $patient_name, $query ) = '';

    if ($upload_id) {
        ########################################################
        ##########Extract pname using uploadid##################
        ########################################################
        $query = "SELECT PatientName FROM mri_upload WHERE UploadID =?";
        my $sth = $dbh->prepare($query);
        $sth->execute($upload_id);
        if ( $sth->rows > 0 ) {
            $patient_name = $sth->fetchrow_array();
        }
    }
    return $patient_name;
}

################################################################
############### getFilePathUsingUploadID########################
################################################################
=pod

=head3 getFilePathUsingUploadID($upload_id)

Functions that gets the file path from the `mri_upload` table using the upload
ID

INPUT: The upload ID

RETURNS: The full path to the uploaded file

=cut


sub getFilePathUsingUploadID {

    my $upload_id = shift;
    my ( $file_path, $query ) = '';

    if ($upload_id) {
        ########################################################
        #######Extract File with full path using upload_id######
        ########################################################
        $query = "SELECT UploadLocation FROM mri_upload WHERE UploadID =?";
        my $sth = $dbh->prepare($query);
        $sth->execute($upload_id);
        if ( $sth->rows > 0 ) {
            $file_path = $sth->fetchrow_array();
        }
    }
    return $file_path;
}


################################################################
###### get number_of_mincCreated & number_of_mincInserted ######
################################################################
=pod

=head3 getNumberOfMincFiles($upload_id)

Function that gets the count of MINC files created and inserted using the
upload ID

INPUT: The upload ID

RETURNS:
  - $minc_created : count of MINC files created
  - $minc_inserted: count of MINC files inserted

=cut


sub getNumberOfMincFiles {
    my $upload_id = shift;
    my ( $minc_created, $minc_inserted, $query ) = '';
    my @row = ();

    if ($upload_id) {
    ############################################################
    ############### Check to see if the uploadID exists ########
    ############################################################
    $query =
        "SELECT number_of_mincCreated, number_of_mincInserted "
      . "FROM mri_upload "
      . "WHERE UploadID =?";

    my $sth = $dbh->prepare($query);
    $sth->execute($upload_id);
    if ( $sth->rows > 0 ) {
        @row = $sth->fetchrow_array();
        $minc_created = $row[0];
        $minc_inserted = $row[1];
        return ($minc_created, $minc_inserted);
       }
    }
}

################################################################
############### spool()#########################################
################################################################
=pod

=head3 spool()

Function that calls the C<Notify->spool> function to log all messages

INPUTS:
 - $this   : Reference to the class
 - $message: Message to be logged in the database
 - $error  : If 'Y' it's an error log , 'N' otherwise
 - $verb   : 'N' for summary messages,
             'Y' for detailed messages (developers)

=cut

sub spool  {
    my ( $message, $error, $verb) = @_;
    $Notify->spool('mri upload runner', 
                   $message, 
                   0, 
        	   'imaging_upload_file.pl',
                   $upload_id,$error, $verb
    );
}

exit $NeuroDB::ExitCodes::SUCCESS;


__END__

=pod

=head1 TO DO

Add a check that the uploaded scan file is accessible by the front end user
(i.e. that the user-group is set properly on the upload directory). Throw an
error and log it, otherwise.

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

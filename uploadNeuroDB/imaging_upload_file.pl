#! /usr/bin/perl
use strict;
use warnings;
use Carp;
use Getopt::Tabular;
use FileHandle;
use File::Temp qw/ tempdir /;
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
my $upload_id = undef;         # The uploadID
my $template  = "ImagingUpload-$hour-$min-XXXXXX";    # for tempdir
my $TmpDir_decompressed_folder =
     tempdir( $template, TMPDIR => 1, CLEANUP => 1 );
my $output              = undef;
my $uploaded_file       = undef;
my $message             = '';
my $verbose             = 0;           	# default for now, run with -verbose option to re-enable
my $notify_detailed     = 'Y';		# notification_spool message flag for messages to be displayed 
				       	# with DETAILED OPTION in the front-end/imaging_uploader 
my $notify_notsummary   = 'N';         	# notification_spool message flag for messages to be displayed 
				       	# with SUMMARY Option in the front-end/imaging_uploader 
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
- Sources the Environment
- Uses the ImagaingUpload class to :
   1) Validate the uploaded file   (set the validation to true)
   2) Run dicomtar.pl on the file  (set the dicomtar to true)
   3) Run tarchiveLoader on the file (set the minc-created to true)
   4) Removes the uploaded file once the previous steps have completed
   5) Update the mri_upload table 

HELP
my $Usage = <<USAGE;
usage: $0 </path/to/UploadedFile> -upload_id [options]
       $0 -help to list options
USAGE
&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV ) || exit 1;
################################################################
############### input option error checking ####################
################################################################

=pod
 1) For those logs before getting the --dbh...they also need to 
     -They need to be inserted
 2) The -patient-name can be included for further validation
=cut

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( $profile && !@Settings::db ) {
    print "\n\tERROR: You don't have a 
    configuration file named '$profile' in:  
    $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit 2;
}
if ( !$ARGV[0] || !$profile ) {
    print $Help;
    print "$Usage\n\tERROR: The path to the Uploaded"
      . "file is not valid or there is no existing profile file \n\n";
    exit 3;
}

if ( !$upload_id ) {
    print $Help;
    print "$Usage\n\tERROR: The Upload_id is missing \n\n";
    exit 4;
}

$uploaded_file = abs_path( $ARGV[0] );
unless ( -e $uploaded_file ) {
    print "\nERROR: Could not find the uploaded file
            $uploaded_file. \nPlease, make sure "
      . "the path to the uploaded file is correct. 
           Upload will exit now.\n\n\n";
    exit 5;
}

################################################################
################ Establish database connection #################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

################################################################
############ Todo: Check to see if the file is accessible#######
## if not, it means that the front-end module###################
## has not changed the user-group properly######################
##Therefore return an error and log the error###################
################################################################


################################################################
################ FileDecompress Object #########################
################################################################
#####################TO DOOO##################################
####Check to see if the file is zipped or compressed before calling the
#### decompress class
#
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
    $message = "\nThe candidate info validation has failed \n";
    spool($message,'Y', $notify_notsummary);
    print $message;
    exit 6;
}

$message = "\nThe candidate info validation has passed \n";
spool($message,'N', $notify_notsummary);

################################################################
############### Run DicomTar  ##################################
################################################################
$output = $imaging_upload->runDicomTar();
if ( !$output ) {
    $imaging_upload->updateMRIUploadTable(
	'Inserting', 0);
    $message = "\nThe dicomtar execution has failed\n";
    spool($message,'Y', $notify_notsummary);
    print $message;
    exit 7;
}
$message = "\nThe dicomtar execution has successfully completed\n";
spool($message,'N', $notify_notsummary);

################################################################
############### Run runTarchiveLoader###########################
################################################################
$output = $imaging_upload->runTarchiveLoader();
$imaging_upload->updateMRIUploadTable('Inserting', 0);
if ( !$output ) {
    $message = "\nThe insertion scripts have failed\n";
    spool($message,'Y', $notify_notsummary); 
    print $message;
    exit 8;
}

################################################################
### If we got this far, dicomTar and tarchiveLoader completed###
#### Remove the uploaded file from the incoming directory#######
################################################################
my $isCleaned = $imaging_upload->CleanUpDataIncomingDir($uploaded_file);
if ( !$isCleaned ) {
    $message = "\nThe uploaded file " . $uploaded_file . " was not removed\n";
    spool($message,'Y', $notify_notsummary);
    print $message;
    exit 9;
}
$message = "\nThe uploaded file " . $uploaded_file . " has been removed\n";
spool($message,'N', $notify_notsummary);

################################################################
############### Spool last completion message ##################
################################################################
my ($minc_created, $minc_inserted) = getNumberMincFiles($upload_id);

$message = "\nThe insertion scripts have completed "
	    . "with $minc_created minc file(s) created, "
	    . "and $minc_inserted minc file(s) "
	    . "inserted into the database \n";
spool($message,'N', $notify_notsummary);

################################################################
############### getPnameUsingUploadID###########################
################################################################
=pod
getPnameUsingUploadID()
Description:
  - Get the patient-name using the upload_id

Arguments:
  $upload_id: The Upload ID

  Returns: $patient_name : The patientName
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
###### get number_of_mincCreated & number_of_mincInserted ######
################################################################
=pod
getNumberMincFiles()
Description:
  - Get the count of minc files created and inserted using the upload_id

Arguments:
  $upload_id: The Upload ID

  Returns: $minc_created and $minc_inserted: count of minc created and inserted
=cut


sub getNumberMincFiles {

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
spool()
Description:
   - Calls the Notify->spool function to log all messages 

Arguments:
 $this      : Reference to the class
 $message   : Message to be logged in the database 
 $error     : if 'Y' it's an error log , 'N' otherwise
 $verb      : 'N' for summary messages, 'Y' for detailed messages (developers)

 Returns    : NULL
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

exit 0;

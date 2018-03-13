#! /usr/bin/perl
use strict;
use warnings;
use Carp;
use Getopt::Tabular;
use FileHandle;
use File::Basename;
use File::Temp qw/ tempdir /;
use Data::Dumper;
use FindBin;
use Cwd qw/ abs_path /;

# These are the NeuroDB modules to be used
use lib "$FindBin::Bin";
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::Notify;
use NeuroDB::MRIProcessingUtility;

my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.24 $ 
    =~ /: (\d+)\.(\d+)/;
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) 
    =localtime(time);
my $date = sprintf(
                "%4d-%02d-%02d %02d:%02d:%02d",
                $year+1900,$mon+1,$mday,$hour,$min,$sec
           );
my $debug       = 0;  
my $message     = '';
my $tarchive_srcloc = '';
my $upload_id   = undef;
my $verbose     = 0;           # default, overwritten if scripts are run with -verbose
my $notify_detailed   = 'Y';   # notification_spool message flag for messages to be displayed 
                               # with DETAILED OPTION in the front-end/imaging_uploader 
my $notify_notsummary = 'N';   # notification_spool message flag for messages to be displayed 
                               # with SUMMARY Option in the front-end/imaging_uploader 
my $profile     = undef;       # this should never be set unless you are in a 
                               # stable production environment
my $reckless    = 0;           # this is only for playing and testing. Don't 
                               # set it to 1!!!
my $force       = 0;           # This is a flag to force the script to run  
                               # Even if the validation has failed
my $no_jiv      = 0;           # Should bet set to 1, if jivs should not be 
                               # created
my $NewScanner  = 1;           # This should be the default unless you are a 
                               # control freak
my $xlog        = 0;           # default should be 0
my $bypass_extra_file_checks=0;# If you need to bypass the extra_file_checks, set to 1.
my $acquisitionProtocol=undef; # Specify the acquisition Protocol also bypasses the checks
my $acquisitionProtocolID;     # acquisition Protocol id
my @checks      = ();          # Initialise the array
my $create_minc_pics    = 0;   # Default is 0, set the option to overide.
my $globArchiveLocation = 0;   # whether to use strict ArchiveLocation strings
                               # or to glob them (like '%Loc')
my $no_nii      = 1;           # skip NIfTI creation by default
my $template    = "TarLoad-$hour-$min-XXXXXX"; # for tempdir
my ($tarchive,%tarchiveInfo,$minc);

################################################################
#### These settings are in a config file (profile) #############
################################################################
my @opt_table = (
                 ["Basic options","section"],

                 ["-profile","string",1, \$profile, "name of config file". 
                 " in ../dicom-archive/.loris_mri"],

                 ["Advanced options","section"],

                 ["-reckless", "boolean", 1, \$reckless,"Upload data to". 
                 " database even if study protocol is not ".
                 "defined or violated."],

                 ["-force", "boolean", 1, \$force,"Forces the script to run". 
                 " even if the validation has failed."],

                 ["-noJIV", "boolean", 1, \$no_jiv,"Prevents the JIVs from being ".
                  "created."],
  
                 ["-mincPath","string",1, \$minc, "The absolute path". 
                  " to minc-file"],

                 ["-tarchivePath","string",1, \$tarchive, "The absolute path". 
                  " to tarchive-file"],

                 ["-uploadID", "string", 1, \$upload_id, "The upload ID " .
                  "from which this MINC was created"],

                 ["-globLocation", "boolean", 1, \$globArchiveLocation,
                  "Loosen the validity check of the tarchive allowing for the". 
                  " possibility that the tarchive was moved to a different". 
                  " directory."],

                 ["-newScanner", "boolean", 1, \$NewScanner,
                  "By default a new scanner will be registered if the data".
                  " you upload requires it. You can risk turning it off."],

                 ["Fancy options","section"],

                 ["-xlog", "boolean", 1, \$xlog, "Open an xterm with a tail".
                  " on the current log file."],

                 ["General options","section"],
                 ["-verbose", "boolean", 1, \$verbose, "Be verbose."],

                 ["-acquisition_protocol","string", 1, \$acquisitionProtocol,
                  "Suggest the acquisition protocol to use."],

                 ["-create_minc_pics", "boolean", 1, \$create_minc_pics,
                  "Creates the minc pics."],

                 ["-bypass_extra_file_checks", "boolean", 1, \$bypass_extra_file_checks,
                  "Bypasses extra_file_checks."],
);


my $Help = <<HELP;
*******************************************************************************
Minc Insertion 
*******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo


The program does the following:

- Loads the created MINC file and then sets the appropriate parameter for
  the loaded object (i.e ScannerID, SessionID,SeriesUID, EchoTime, 
                     PendingStaging, CoordinateSpace , OutputType , FileType
                     ,TarchiveSource and Caveat)
- Extracts the correct acquition protocol
- Registers the scan into db by first changing the minc-path and setting extra
  parameters
- Finally sets the series notification

HELP
my $Usage = <<USAGE;
usage: $0 </path/to/DICOM-tarchive> [options]
       $0 -help to list options

USAGE
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;


# input option error checking
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }


if ($profile && !@Settings::db) { 
    print "\n\tERROR: You don't have a ".
    "configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit 2; 
}

if (!$profile) { 
    print $Help; 
    print "$Usage\n\tERROR: You must specify a valid ".
    "and existing profile.\n\n";  
    exit 3; 
}

if ( !($tarchive xor $upload_id) ) {
    print "\nERROR: You should either specify an upload ID or a tarchive ".
        "path. Make sure that you set only one of those options. ".
        "Upload will exit now.\n\n\n";
    exit; #TODO 1: use exit code from ExitCodes once it is merged
}

if ($tarchive && !(-e $tarchive) ) {
    print "\nERROR: Could not find archive $tarchive. \nPlease, make sure ".
          " the path to the archive is correct. Upload will exit now.\n\n\n";
    exit 4;
}
unless (-e $minc) {
    print "\nERROR: Could not find minc $minc. \nPlease, make sure the ".
          "path to the minc is correct. Upload will exit now.\n\n\n";
    exit 5;
}




################################################################
############### Establish database connection ##################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

################################################################
########### Create the Specific Log File #######################
################################################################
my $data_dir = NeuroDB::DBI::getConfigSetting(
                    \$dbh,'dataDirBasepath'
                    );
if (defined (NeuroDB::DBI::getConfigSetting(\$dbh,'no_nii'))) {
    $no_nii = NeuroDB::DBI::getConfigSetting(
                       \$dbh,'no_nii'
                        ) 
}
my $jiv_dir  = $data_dir.'/jiv';
my $TmpDir   = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
my @temp     = split(/\//, $TmpDir);
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs";
my $tarchiveLibraryDir = &NeuroDB::DBI::getConfigSetting(
                       \$dbh,'tarchiveLibraryDir'
                       );
$tarchiveLibraryDir    =~ s/\/$//g;
if (!-d $LogDir) { 
    mkdir($LogDir, 0770); 
}
my $logfile  = "$LogDir/$templog.log";
print "\nlog dir is $LogDir and log file is $logfile \n" if $verbose;
open LOG, ">>", $logfile or die "Error Opening $logfile";
LOG->autoflush(1);
# strings needed for the logHeader, if not set, as an argument, use empty string
my $source_data_for_log = $tarchive // "";
my $upload_id_for_log = $upload_id // "";
&logHeader();

print LOG "\n==> Successfully connected to database \n" if $verbose;

################################################################
################## MRIProcessingUtility object #################
################################################################
my $utility = NeuroDB::MRIProcessingUtility->new(
                  \$dbh,$debug,$TmpDir,$logfile,
                  $verbose
              );

################################################################
############ Construct the notifier object #####################
################################################################
my $notifier = NeuroDB::Notify->new(\$dbh);



################################################################
#################### Check is_valid column #####################
################################################################
my ( $is_valid, $ArchiveLocation );
if ($tarchive) {
    # if the tarchive path is given as an argument, find the associated UploadID
    # and check if IsTarchiveValidated is set to 1.
    $ArchiveLocation = $tarchive;
    $ArchiveLocation    =~ s/$tarchiveLibraryDir\/?//g;

    my $where = "WHERE t.ArchiveLocation='$tarchive'";
    if ($globArchiveLocation) {
        $where = "WHERE t.ArchiveLocation LIKE '%" . basename($tarchive) . "'";
    }
    my $query = "SELECT m.IsTarchiveValidated FROM mri_upload m " .
        "JOIN tarchive t on (t.TarchiveID = m.TarchiveID) $where ";
    print $query . "\n" if $debug;
    $is_valid = $dbh->selectrow_array($query);

    ## Setup  for the notification_spool table ##
    # get the tarchive_srcloc from $tarchive
    $query = "SELECT SourceLocation" .
        " FROM tarchive t $where";
    my $sth = $dbh->prepare($query);
    $sth->execute();
    $tarchive_srcloc = $sth->fetchrow_array;
    # get the $upload_id from $tarchive_srcloc
    $query =
        "SELECT UploadID FROM mri_upload "
            . "WHERE DecompressedLocation =?";
    $sth = $dbh->prepare($query);
    $sth->execute($tarchive_srcloc);
    $upload_id = $sth->fetchrow_array;
    ## end of setup IDs for notification_spool table
} elsif ($upload_id) {
    # if the uploadID is passed as an argument, verify that the tarchive was
    # validated
    (my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT
      m.IsTarchiveValidated,
      t.ArchiveLocation
    FROM
      mri_upload m JOIN tarchive t ON (t.TarchiveID = m.TarchiveID)
    WHERE
      m.UploadID = ?
QUERY
    print $query . "\n" if $debug;
    my $sth = $dbh->prepare($query);
    $sth->execute($upload_id);
    my @array        = $sth->fetchrow_array;
    $is_valid        = $array[0];
    $ArchiveLocation = $array[1];
}

if (($is_valid == 0) && ($force==0)) {
    $message = "\n ERROR: The validation has failed. ".
               "Either run the validation again and fix ".
               "the problem. Or use -force to force the ".
               "execution.\n\n";
    print $message;
    $utility->writeErrorLog($message,6,$logfile); 
    $notifier->spool('tarchive validation', $message, 0,
                    'minc_insertion.pl', $upload_id, 'Y', 
                    $notify_notsummary);
    exit 6;
}

################################################################
############## Construct the tarchiveinfo Array ################
################################################################
%tarchiveInfo = $utility->createTarchiveArray(
                    $ArchiveLocation, $globArchiveLocation
                );

################################################################
############ Get the $center_name, $centerID ##############
################################################################
my ($center_name, $centerID) = $utility->determinePSC(
                    \%tarchiveInfo, 0, $upload_id
                );

################################################################
#### Determine the ScannerID ###################################
################################################################
my $scannerID = $utility->determineScannerID(
                    \%tarchiveInfo, 0, $centerID, $NewScanner, $upload_id
                );

################################################################
###### Construct the $subjectIDsref array ######################
################################################################
my $subjectIDsref = $utility->determineSubjectID(
                        $scannerID, \%tarchiveInfo, 0, $upload_id
                    );

################################################################
################# Define the $CandMismatchError ################
################################################################
# Check the CandID/PSCID Match It's possible that the CandID ### 
# exists, but doesn't match the PSCID. This will fail further ##
# down silently, so we explicitly check that the data is #######
# correct here #################################################
################################################################

my $CandMismatchError = undef;
$CandMismatchError= $utility->validateCandidate(
                                $subjectIDsref,
                                $tarchiveInfo{'SourceLocation'});

my $logQuery = "INSERT INTO MRICandidateErrors".
              "(SeriesUID, TarchiveID,MincFile, PatientName, Reason) ".
              "VALUES (?, ?, ?, ?, ?)";
my $candlogSth = $dbh->prepare($logQuery);

################################################################
#### Loads/Creates File object and maps dicom fields ###########
################################################################
my $file = $utility->loadAndCreateObjectFile($minc, $upload_id);

################################################################
##### Optionally do extra filtering, if needed #################
################################################################
if (defined(&Settings::filterParameters)) {
    print LOG "\n--> using user-defined filterParameters for $minc\n"
    if $verbose;
    Settings::filterParameters(\$file);
}

################################################################
# We already know the PatientName is bad from step 5a, but #####
# had to wait until this point so that we have the #############
# SeriesUID and MincFile name to compute the md5 hash. Do it ###
# before computing the hash because there's no point in ########
# going that far if we already know it's fault. ################
################################################################

if (defined($CandMismatchError)) {
    $message = "\nCandidate Mismatch Error is $CandMismatchError\n";
    print LOG $message;
    print LOG " -> WARNING: This candidate was invalid. Logging to
              MRICandidateErrors table with reason $CandMismatchError";
    $candlogSth->execute(
        $file->getParameter('series_instance_uid'),
        $tarchiveInfo{'TarchiveID'},
        $minc,
        $tarchiveInfo{'PatientName'},
        $CandMismatchError
    );
    
    $notifier->spool('tarchive validation', $message, 0,
                    'minc_insertion.pl', $upload_id, 'Y', 
                    $notify_notsummary);

    exit 7 ;
}

################################################################
####### Get the $sessionID and $requiresStaging ################
################################################################
my ($sessionID, $requiresStaging) =
    NeuroDB::MRI::getSessionID( 
        $subjectIDsref, 
        $tarchiveInfo{'DateAcquired'},
        \$dbh, $subjectIDsref->{'subprojectID'}
   );

################################################################
############ Compute the md5 hash ##############################
################################################################
my $unique = $utility->computeMd5Hash( $file, $upload_id );
if (!$unique) { 
    $message = "\n--> WARNING: This file has already been uploaded!\n";  
    print $message if $verbose;
    print LOG $message; 
    $notifier->spool('tarchive validation', $message, 0,
                    'minc_insertion.pl', $upload_id, 'Y', 
                    $notify_notsummary);
    exit 8; 
} 

################################################################
## at this point things will appear in the database ############
## Set some file information ###################################
################################################################
$file->setFileData('ScannerID', $scannerID);
$file->setFileData('SessionID', $sessionID);
$file->setFileData('SeriesUID', $file->getParameter('series_instance_uid'));
$file->setFileData('EchoTime', $file->getParameter('echo_time'));
$file->setFileData('PendingStaging', $requiresStaging);
$file->setFileData('CoordinateSpace', 'native');
$file->setFileData('OutputType', 'native');
$file->setFileData('FileType', 'mnc');
$file->setFileData('TarchiveSource', $tarchiveInfo{'TarchiveID'});
if (defined($acquisitionProtocol)) {
    $file->setFileData('Caveat', 1);
} else {
    $file->setFileData('Caveat', 0);
}

################################################################
## Get acquisition protocol (identify the volume) ##############
################################################################
($acquisitionProtocol,$acquisitionProtocolID,@checks)
  = $utility->getAcquisitionProtocol(
      $file,
      $subjectIDsref,
      \%tarchiveInfo,
      $center_name,
      $minc,
      $acquisitionProtocol,
      $bypass_extra_file_checks,
      $upload_id
    );


if($acquisitionProtocol =~ /unknown/) {
   $message = "\n  --> The minc file cannot be registered ".
              "since the AcquisitionProtocol is unknown \n";

   print LOG $message;
   $notifier->spool('minc insertion', $message, 0,
                   'minc_insertion.pl', $upload_id, 'Y', 
                   $notify_notsummary);
   exit 9;
}

################################################################
# Register scans into the database.  Which protocols ###########
# to keep optionally controlled by the config file #############
################################################################

my $acquisitionProtocolIDFromProd = $utility->registerScanIntoDB(
    \$file,               \%tarchiveInfo, $subjectIDsref,
    $acquisitionProtocol, $minc,          \@checks,
    $reckless,            $sessionID,     $upload_id
);

if ((!defined$acquisitionProtocolIDFromProd)
   && (defined(&Settings::isFileToBeRegisteredGivenProtocol))
   ) {
   $message = "\n  --> The minc file cannot be registered ".
                "since $acquisitionProtocol ".
                "does not exist in $profile ". 
                "or it did not pass the extra_file_checks\n";
   print LOG $message;
   $notifier->spool('minc insertion', $message, 0,
                   'minc_insertion', $upload_id, 'Y',
                   $notify_notsummary);
    exit 10;
}
################################################################
### Add series notification ####################################
################################################################
$message =
	"\n" . $subjectIDsref->{'CandID'} . " " .
    	$subjectIDsref->{'PSCID'} ." " .
    	$subjectIDsref->{'visitLabel'} .
    	"\tacquired " . $file->getParameter('acquisition_date') .
    	"\t" . $file->getParameter('series_description') .
	"\n";
$notifier->spool('mri new series', $message, 0,
    		'minc_insertion.pl', $upload_id, 'N', 
		$notify_detailed);

if ($verbose) {
    print "\nFinished file:  ".$file->getFileDatum('File')." \n";
}
################################################################
###################### Creation of Jivs ########################
################################################################
if (!$no_jiv) {
    print "\nMaking JIV\n" if $verbose;
    NeuroDB::MRI::make_jiv(\$file, $data_dir, $jiv_dir);
}

################################################################
###################### Creation of NIfTIs ######################
################################################################
unless ($no_nii) {
    print "\nCreating NIfTI files\n" if $verbose;
    NeuroDB::MRI::make_nii(\$file, $data_dir);
}

################################################################
################# Create minc-pics #############################
################################################################
if ($create_minc_pics) {
    print "\nCreating Minc Pics\n" if $verbose;
    NeuroDB::MRI::make_minc_pics(\$dbh,
                                  $tarchiveInfo{TarchiveID},
                                  $profile,
                                  1,
                                  $debug,
                                  $verbose);
    # Set minFileID to 1: minFileID $row[1] & maxFileID $row[1]
}

################################################################
################## Succesfully completed #######################
################################################################
exit 0;

sub logHeader () {
    print LOG "
----------------------------------------------------------------
            AUTOMATED DICOM DATA UPLOAD
----------------------------------------------------------------
*** Date and time of upload    : $date
*** Location of source data    : $source_data_for_log
*** tmp dir location           : $TmpDir
*** Upload ID of source data   : $upload_id_for_log
";
}

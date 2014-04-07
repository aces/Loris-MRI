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
my $debug       = 1;  
my $message     = '';
my $verbose     = 1;           # default for now
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
my $globArchiveLocation = 0;   # whether to use strict ArchiveLocation strings
                               # or to glob them (like '%Loc')
my $template    = "TarLoad-$hour-$min-XXXXXX"; # for tempdir
my ($tarchive,%tarchiveInfo,$minc);

################################################################
#### These settings are in a config file (profile) #############
################################################################
my @opt_table = (
                 ["casic options","section"],

                 ["-profile","string",1, \$profile, "name of config file". 
                 " in ~/.neurodb."],

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

);


my $Help = <<HELP;
*******************************************************************************
Minc Insertion 
*******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo


The program does the following:

- Loads the created minc file and then sets the appropriate parameter for 
  the loaded object (i.e ScannerID, SessionID,SeriesUID, EchoTime, 
                     PendingStaging, CoordinateSpace , OutputType , FileType
                     ,TarchiveSource and Caveat)
- Extracts the correct acquitionprotocol
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
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }


if ($profile && !defined @Settings::db) { 
    print "\n\tERROR: You don't have a ".
    "configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n";
    exit 2; 
}

if (!$profile) { 
    print $Help; 
    print "$Usage\n\tERROR: You must specify a valid ".
    "and existing profile.\n\n";  
    exit 3; 
}


unless (-e $tarchive) {
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
########### Create the Specific Log File #######################
################################################################
my $data_dir = $Settings::data_dir;
my $jiv_dir = $data_dir.'/jiv';
my $TmpDir = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
my @temp     = split(/\//, $TmpDir);
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs"; 
print "log dir is $LogDir \n";
if (!-d $LogDir) { 
    mkdir($LogDir, 0700); 
}
my $logfile  = "$LogDir/$templog.log";
open LOG, ">>", $logfile or die "Error Opening $logfile";
LOG->autoflush(1);
&logHeader();

################################################################
############### Establish database connection ##################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";


################################################################
################## MRIProcessingUtility object #################
################################################################
my $utility = NeuroDB::MRIProcessingUtility->new(
                  \$dbh,$debug,$TmpDir,$logfile,
                  $verbose
              );

################################################################
#################### Check is_valid column #####################
################################################################
my $where = "WHERE t.ArchiveLocation='$tarchive'";
if ($globArchiveLocation) {
    $where = "WHERE t.ArchiveLocation LIKE '%/".basename($tarchive)."'";
}
my $query = "SELECT m.IsValidated FROM mri_upload m " .
            "JOIN tarchive t on (t.TarchiveID = m.TarchiveID) $where ";
print $query . "\n";
my $is_valid = $dbh->selectrow_array($query);

if (($is_valid == 0) && ($force==0)) {
    $message = "\n ERROR: The validation has failed. ".
               "Either run the validation again and fix ".
               "the problem. Or use -force to force the ".
               "execution.\n\n";
    print $message;
    $utility->writeErrorLog($message,6,$logfile); 
    exit 6;
}

################################################################
############## Construct the tarchiveinfo Array ################
################################################################
%tarchiveInfo = $utility->createTarchiveArray(
                    $tarchive,$globArchiveLocation
                );

################################################################
############ Get the $psc,$center_name, $centerID ##############
################################################################
my ($psc,$center_name, $centerID) = $utility->determinePSC(\%tarchiveInfo,0);

################################################################
#### Determine the ScannerID ###################################
################################################################
my $scannerID = $utility->determineScannerID(
                    \%tarchiveInfo,0,$centerID,
                    $NewScanner
                );

################################################################
###### Construct the $subjectIDsref array ######################
################################################################
my $subjectIDsref = $utility->determineSubjectID(
                        $scannerID,\%tarchiveInfo,0
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
$CandMismatchError= $utility->validateCandidate($subjectIDsref);

my $logQuery = "INSERT INTO MRICandidateErrors".
              "(SeriesUID, TarchiveID,MincFile, PatientName, Reason) ".
              "VALUES (?, ?, ?, ?, ?)";
my $candlogSth = $dbh->prepare($logQuery);

################################################################
############ Construct the notifier object #####################
################################################################
my $notifier = NeuroDB::Notify->new(\$dbh);

################################################################
#### Loads/Creates File object and maps dicom fields ###########
################################################################
my $file = $utility->loadAndCreateObjectFile($minc);

################################################################
##### Optionally do extra filtering, if needed #################
################################################################
if (defined(&Settings::filterParameters)) {
    print LOG " --> using user-defined filterParameters for $minc\n"
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
    print LOG "Candidate Mismatch Error is $CandMismatchError\n";
    print LOG " -> WARNING: This candidate was invalid. Logging to
              MRICandidateErrors table with reason $CandMismatchError";
    $candlogSth->execute(
        $file->getParameter('series_instance_uid'),
        $tarchiveInfo{'TarchiveID'},
        $minc,
        $tarchiveInfo{'PatientName'},
        $CandMismatchError
    );
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
my $unique = $utility->computeMd5Hash($file);
if (!$unique) { 
    print "--> WARNING: This file has already been uploaded! \n"  if $debug;
    print LOG " --> WARNING: This file has already been uploaded!"; 
    exit 8; 
} 

################################################################
## at this point things will appear in the database ############
## Set some file information ###################################
################################################################
$file->setParameter('ScannerID', $scannerID);
$file->setFileData('SessionID', $sessionID);
$file->setFileData('SeriesUID', $file->getParameter('series_instance_uid'));
$file->setFileData('EchoTime', $file->getParameter('echo_time'));
$file->setFileData('PendingStaging', $requiresStaging);
$file->setFileData('CoordinateSpace', 'native');
$file->setFileData('OutputType', 'native');
$file->setFileData('FileType', 'mnc');
$file->setFileData('TarchiveSource', $tarchiveInfo{'TarchiveID'});
$file->setFileData('Caveat', 0);

################################################################
## Get acquisition protocol (identify the volume) ##############
################################################################
my ($acquisitionProtocol,$acquisitionProtocolID,@checks)
  = $utility->getAcquisitionProtocol(
        $file,
        $subjectIDsref,
        \%tarchiveInfo,$center_name,
        $minc
    );

if($acquisitionProtocol =~ /unknown/) {
   print LOG " --> The minc file cannot be registered since the ".
             "AcquisitionProtocol IS unknown";
   exit 9;
}

################################################################
# Register scans into the database.  Which protocols ###########
# to keep optionally controlled by the config file #############
################################################################

$utility->registerScanIntoDB(
    \$file, \%tarchiveInfo,$subjectIDsref, 
    $acquisitionProtocol, $minc, \@checks, 
    $reckless, $tarchive, $sessionID
);

################################################################
### Add series notification ####################################
################################################################
$notifier->spool(
    'mri new series', $subjectIDsref->{'CandID'} . " " .
    $subjectIDsref->{'PSCID'} ." " .
    $subjectIDsref->{'visitLabel'} .
    "\tacquired " . $file->getParameter('acquisition_date')
    . "\t" . $file->getParameter('series_description'),
    $centerID
);

print "\nFinished file:  ".$file->getFileDatum('File')." \n" if $debug;


################################################################
###################### Creating of Jivs ########################
################################################################
if (!$no_jiv) {
    print "Making JIV\n" if $verbose;
    NeuroDB::MRI::make_jiv(\$file, $data_dir, $jiv_dir);
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
*** Location of source data    : $tarchive
*** tmp dir location           : $TmpDir
";
}

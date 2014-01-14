#! /usr/bin/perl
use strict;
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
my $verbose     = 1;           # default for now

my $profile     = undef;       # this should never be set unless you are in a 
                               # stable production environment
my $reckless    = 0;           # this is only for playing and testing. Don't 
                               #set it to 1!!!
my $force       = 0;           # This is a flag to force the script to run  
                               # Even if the validation has failed

my $NewScanner  = 1;           # This should be the default unless you are a 
                               #control freak

                               # Even if the validation has failed
my $xlog        = 0;           # default should be 0
my $globArchiveLocation = 0;   # whether to use strict ArchiveLocation strings
                               # or to glob them (like '%Loc')

my $template         = "TarLoad-$hour-$min-XXXXXX"; # for tempdir

# establish database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";


my ($PSCID, $md5sumArchive, $visitLabel, $gender);

my ($tarchive,%tarchiveInfo,$minc);

my $User        = `whoami`;

my $converter        = $Settings::converter;

my $mail_user        = $Settings::mail_user;
my $newTarchiveLocation = undef;
my $valid_study = 0;
my %tarchiveInfo;

my @opt_table = (
                 ["casic options","section"],

                 ["-profile     ","string",1, \$profile, "name of config file 
                 in ~/.neurodb."],

                 ["Advanced options","section"],

                 ["-reckless", "boolean", 1, \$reckless,"Upload data to 
                 database even if study protocol is not defined or violated."],

                 ["-force", "boolean", 1, \$force,"Forces the script to run 
                 even if the validation has failed."],


                 ["-globLocation", "boolean", 1, \$globArchiveLocation,"Loosen 
                  the validity check of the tarchive allowing for the 
                  possibility that the tarchive was moved to a different 
                  directory."],

                 ["-newScanner", "boolean", 1, \$NewScanner,
                  "By default a new scanner will be registered if the data you 
                   upload requires it. You can risk turning it off."],

                 ["Fancy options","section"],
                 # fixme      ["-keeptmp", "boolean", 1, \$keep, "Keep temp 
                 ##dir. Makes sense if have infinite space on your server."],
                 ["-xlog", "boolean", 1, \$xlog, "Open an xterm with a tail on
                  the current log file."],
                 );


my $Help = <<HELP;
*******************************************************************************
Dicom Validator 
*******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo


The program does the following validation
====explain====

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
    print "\n\tERROR: You don't have a 
    configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n";
    exit 33; 
}
if(!$ARGV[0] || !$profile) { 
    print $Help; print "$Usage\n\tERROR: You must specify a valid 
    tarchive and an existing profile.\n\n";  
    exit 33; 
}

my $tarchive = abs_path($ARGV[0]);
unless (-e $tarchive) {
    print "\nERROR: Could not find archive $tarchive. \nPlease, make sure the 
            path to the archive is correct. Upload will exit now.\n\n\n";
    exit 33;
}

my $minc = abs_path($ARGV[1]);
unless (-e $tarchive) {
    print "\nERROR: Could not find minc $minc. \nPlease, make sure the 
            path to the minc is correct. Upload will exit now.\n\n\n";
    exit 33;
}

#######################################################
#######################################################
###########Create the Specific Log File################
#######################################################

my $data_dir         = $Settings::data_dir;
my $TmpDir = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
my @temp     = split(/\//, $TmpDir);
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs"; if (!-d $LogDir) { mkdir($LogDir, 0700); }
my $logfile  = "$LogDir/$templog.log";
print "logdir is $LogDir and logfile is $logfile \n";
open LOG, ">>", $logfile or die "Error Opening $logfile";
LOG->autoflush(1);
print LOG "testing";


=pod

1) Get the tarchive 
2  Get the minc

=cut


################################################################
##############Determine if the validation has passed for not####
################################################################

my $where = "WHERE ArchiveLocation='$tarchive'";
if($globArchiveLocation) {
    $where = "WHERE ArchiveLocation LIKE '%/".basename($tarchive)."'";
}
my $query = "SELECT IsValidated FROM tarchive ";
$query = $query . $where;
print $query. "\n";

my $is_valid = $dbh->selectrow_array($query);


################################################################
#######################Construct the tarchiveinfo Array#########
################################################################
%tarchiveInfo = createTarchiveArray($tarchive,\$dbh,0);
print "tarchive is $tarchive";

################################################################
##################Get the $psc,$center_name, $centerID##########
################################################################
my ($psc,$center_name, $centerID) = determinPSC(%tarchiveInfo,0);


################################################################
################################################################
####determin the ScannerID ##################################### 
################################################################
################################################################
my $scannerID = determinScannerID(%tarchiveInfo,0);




################################################################
################################################################
######Construct the $subjectIDsref array########################
################################################################
################################################################
my $subjectIDsref = determinSubjectID($scannerID,%tarchiveInfo,0);
 print Dumper($subjectIDsref);



################################################################
################################################################
#####Define the $CandMismatchError##############################
################################################################
################################################################
my $CandMismatchError;
my $logQuery = "INSERT INTO MRICandidateErrors (SeriesUID, TarchiveID, MincFile, PatientName, Reason) VALUES (?, ?, ?, ?, ?)";
my $candlogSth = $dbh->prepare($logQuery);

if ($subjectIDsref->{'isPhantom'}) {
    # CandID/PSCID errors don't apply to phantoms, so we don't want to trigger
    # the check which aborts the insertion
    $CandMismatchError = undef;
}
   ##if the validation has passed and force is false###
   ###Then the CandMismatchError is null or undef
if (($is_valid) and !($force)){
    $CandMismatchError = undef;
}


###################################################
# ----- STEP 6: Get the SessionID
###################################################

my ($sessionID, $requiresStaging) =
    NeuroDB::MRI::getSessionID(
        $subjectIDsref, $tarchiveInfo{'DateAcquired'},
         \$dbh, $subjectIDsref->{'subprojectID'}
    );



#####################################################
#### Load/Create create File object##################
#####And map dicom fields############################
####################################################
my $file = loadAndCreateObjectFile($minc,\$dbh);

############################################################
##optionally do extra filtering, if needed##################
############################################################
if( defined( &Settings::filterParameters )) {
    print LOG " --> using user-defined filterParameters for $minc\n"
    if $verbose;
    Settings::filterParameters(\$file);
}

############################################################
# We already know the PatientName is bad from step 5a, but#
## had to wait until this point so that we have the#########
##SeriesUID and MincFile name compute the md5 hash. Do it###
## before computing the hash because there's no point in####
##going that far if we already know it's fault.#############
############################################################

print LOG "Candidate Mismatch Error is $CandMismatchError\n";

if(defined($CandMismatchError)) {
    print LOG " -> WARNING: This candidate was invalid. Logging to
              MRICandidateErrors table with reason $CandMismatchError";
    $candlogSth->execute(
        $file->getParameter('series_instance_uid'),
        $tarchiveInfo{'TarchiveID'},
        $minc,
        $tarchiveInfo{'PatientName'},
        $CandMismatchError
    );
    exit;  ##replaces next
}

#############################################################
##############compute the md5 hash###########################
#############################################################
my $unique = computeMd5Hash($file);
if (!$unique) { 
    print LOG " --> WARNING: This file has already been uploaded!"; 
    exit; 
} 

 
####################################################
###at this point things will appear in the database# 
#####Set some file information#####################
####################################################
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
        
####################################################
##get acquisition protocol (identify the volume)####
####################################################
my ($acquisitionProtocol,$acquisitionProtocolID,$checks)
  = getAcquisitionProtocol(
        $center_name, $subjectIDsref,$file, $dbh, $minc,$file
    );

#####################################################
# Register scans into the database.  Which protocols# 
###to keep optionally controlled by the config file##
#####################################################
registerScanIntoDB($acquisitionProtocol,$minc,$file,$data_dir,$checks);

print "\nFinished file:  ".$file->getFileDatum('File')." \n" if $debug;



sub registerScanIntoDB() {

    my ($acquisitionProtocol,$minc,$file,$data_dir,@checks) = @_;

        ########################################################
        # Register scans into the database.  Which protocols to#
        # keep optionally controlled by the config file.########
        ########################################################
    if ((!defined(&Settings::isFileToBeRegisteredGivenProtocol)
        || $reckless
        || (defined(&Settings::isFileToBeRegisteredGivenProtocol) 
            && Settings::isFileToBeRegisteredGivenProtocol(
                $acquisitionProtocol)
           )
        ) 
        && $checks[0] !~ /exclude/) {

        ########################################################
        # convert the textual scan_type into the scan_type id###
        ########################################################
        my $acquisitionProtocolID = &NeuroDB::MRI::scan_type_text_to_id(
                                        $acquisitionProtocol, \$dbh
                                    );
        $file->setFileData('AcquisitionProtocolID', $acquisitionProtocolID);
        print "Acq protocol: $acquisitionProtocol ID: $acquisitionProtocolID\n"
        if $debug;

        ########################################################
        # set Date_taken = last modification timestamp########## 
        #(can't seem to get creation timestamp)#################
        ########################################################
        my $Date_taken = (stat($minc))[9];
        # rename and move files
        my $minc_protocol_identified = &move_minc(\$minc, $subjectIDsref,
                                        $acquisitionProtocol, \$file
                                       );
        my $file_path   =   $minc;
        $file_path      =~  s/$data_dir\///i;
        print "new NAME: ".$minc_protocol_identified ."\n" if $debug;
        $file->setFileData('File', $file_path);

        ########################################################
        # If tarchive library dir is not defined,###############
        # Or if tarchive library is defined and the tarchive is#
        # in a year subfolder of the tarchive library dir#######
        #   -> the new tarchive location is $tarchive.##########   
        ########################################################
        if ((!defined($Settings::tarchiveLibraryDir)) 
            || ((defined($Settings::tarchiveLibraryDir))
            &&($tarchive =~ m/$Settings::tarchiveLibraryDir\/\d\d\d\d\//i))) {
            $newTarchiveLocation = $tarchive;

        ########################################################
        # if the tarchive has not been moved yet################ 
        #($valid_study undefined)-> move the tarchive from the##
        ## inbox into the tarchive library######################
        ########################################################
        } elsif (!$valid_study) {

            $newTarchiveLocation =  
            moveAndUpdateTarchive(%tarchiveInfo,$tarchive);

            ########################################################
            ####record which tarchive was used to make this file####
            ########################################################
            my $tarchive_path   =   $newTarchiveLocation;
            $tarchive_path      =~  s/$data_dir\///i;
            $file->setParameter('tarchiveLocation', $tarchive_path);
            $file->setParameter('tarchiveMD5', $tarchiveInfo{'md5sumArchive'});

            ########################################################
            # mark the study as valid because at least one volume### 
            ##will be nserted into the DB###########################
            ########################################################
            $valid_study = 1;

            ########################################################
            # register into the db fixme if I ever want a dry run## 
            ########################################################
            print "Registering file into db\n" if $debug;
            my $fileID;
            $fileID = &NeuroDB::MRI::register_db(\$file);
            print "FileID: $fileID\n" if $debug;
    
            ########################################################
            ###update mri_acquisition_dates table###################
            ########################################################
            &update_mri_acquisition_dates($sessionID, $tarchiveInfo{'DateAcquired'}
                                      , \$dbh
            );
        }
    }
}

sub moveAndUpdateTarchive {
    my ($tarchiveInfo,$tarchive) = @_;

    print "Moving tarchive into library\n" if $debug;
    $newTarchiveLocation = $Settings::tarchiveLibraryDir."/".
    substr($tarchiveInfo{'DateAcquired'}, 0, 4);

    ########################################################
    #####make the directory if it does not yet exist########
    ########################################################
    unless(-e $newTarchiveLocation) { 
        mkdir($newTarchiveLocation, 0755); 
    }
    ########################################################
    #######determine the new name of the tarchive###########
    ########################################################
    my $newTarchiveFilename = basename($tarchive);
    $newTarchiveLocation .= "/".$newTarchiveFilename;
       
    ########################################################
    ######move the tarchive#################################
    ########################################################
    my $mvTarchiveCmd = "mv $tarchive $newTarchiveLocation";
    `$mvTarchiveCmd`;   
    
    ########################################################
    # now update tarchive table to store correct location###
    ########################################################
    $dbh->do("UPDATE tarchive SET ArchiveLocation=".
              $dbh->quote($newTarchiveLocation)." WHERE DicomArchiveID="
             .$dbh->quote($tarchiveInfo{'DicomArchiveID'})
            );

  return $newTarchiveLocation;
}
 

sub loadAndCreateObjectFile{

    my ($minc, $dbhr) = @_;
    $dbh = $$dbhr;

    ############################################################
    ################create File object##########################
    ############################################################
    my $file = NeuroDB::File->new(\$dbh);

    ############################################################
    ##########load File object##################################
    ############################################################
    print LOG "\n==> Loading file from disk $minc\n" if $verbose;
    $file->loadFileFromDisk($minc);
   
    ############################################################
    ############# map dicom fields##############################
    ############################################################
    print LOG " --> mapping DICOM parameter for $minc\n" if $verbose;
    NeuroDB::MRI::mapDicomParameters(\$file);
    return $file;
}


# compute the md5 hash
sub computeMd5Hash {
    my ($file) = @_;

    print LOG "==> computing md5 hash for MINC body.\n" if $verbose;
    my $md5hash = &NeuroDB::MRI::compute_hash(\$file);
    print LOG " --> md5: $md5hash\n" if $verbose;
    $file->setParameter('md5hash', $md5hash);
    my $unique = NeuroDB::MRI::is_unique_hash(\$file);
    return $unique;
}




sub getAcquisitionProtocol {

    my ($center_name, $subjectIDsref,$file, $dbh, $minc,$file) = @_;

    ####################################################
    ##get acquisition protocol (identify the volume)####
    ####################################################
    print LOG "==> verifying acquisition protocol\n" if $verbose;
    my $acquisitionProtocol = &NeuroDB::MRI::identify_scan_db(
                               $center_name, \$subjectIDsref,
                                \$file, \$dbh, $minc
                              );
    print LOG "Acquisition protocol is $acquisitionProtocol\n";
    my @checks = ();
    my $acquisitionProtocolID;
    if($acquisitionProtocol !~ /unknown/) {
        $acquisitionProtocolID =
        &NeuroDB::MRI::scan_type_text_to_id(
        $acquisitionProtocol, \$dbh
        );
     @checks = extra_file_checks($acquisitionProtocolID, $file, $subjectIDsref->{'CandID'}, $subjectIDsref->{'visitLabel'}, $tarchiveInfo{'PatientName'});
     print LOG "Worst error: $checks[0]\n" if $debug;
     return ($acquisitionProtocol,$acquisitionProtocolID,$checks);
    }
}

sub determinSubjectID {
    my ($scannerID,%tarchiveinfo,$to_log) = @_;
    $to_log = 1 unless defined $to_log;

    if(!defined(&Settings::getSubjectIDs)) {
        if ($to_log) {
            $message =  "\nERROR: Profile does not contain getSubjectIDs routine.
                         Upload will exit now.\n\n";
            &writeErrorLog($logfile, $message, 66); exit 66;
        }
    }
    my $subjectIDsref = Settings::getSubjectIDs($tarchiveInfo{'PatientName'},
                                            $tarchiveInfo{'PatientID'},
                                            $scannerID,
                                            \$dbh);
    if ($to_log) {
        print LOG "\n==> Data found for candidate   : $subjectIDsref->{'CandID'} 
                  - $subjectIDsref->{'PSCID'} - Visit: 
                  $subjectIDsref->{'visitLabel'} - Acquired :
                  $tarchiveInfo{'DateAcquired'}\n";
    }
    return $subjectIDsref;
}



sub createTarchiveArray {
    my ($tarchive, $dbhr) = @_;
    $dbh = $$dbhr;

    my $where = "ArchiveLocation='$tarchive'";
    if($globArchiveLocation) {
        $where = "ArchiveLocation LIKE '%/".basename($tarchive)."'";
    }
    my $query = "SELECT PatientName, PatientID, PatientDoB, md5sumArchive, 
                 DateAcquired, DicomArchiveID, PatientGender, 
                 ScannerManufacturer, ScannerModel, ScannerSerialNumber,
                 ScannerSoftwareVersion, neurodbCenterName, TarchiveID FROM 
                 tarchive WHERE $where";
    print $query. "\n";
    my $sth = $dbh->prepare($query); $sth->execute();
    my %tarchiveInfo;

    if ($sth->rows > 0) {
        my $tarchiveInfoRef = $sth->fetchrow_hashref();
        %tarchiveInfo = %$tarchiveInfoRef;
    } else {
        $message = "\n ERROR: Only archived data can be uploaded. This seems
                    not to be a valid archive for this study!\n\n";
        &writeErrorLog($logfile, $message, 77); exit 77;
    }

    return %tarchiveInfo;

}


sub determinScannerID {
    my (%tarchiveinfo,$to_log) = @_;
    $to_log = 1 unless defined $to_log;
    if ($to_log) {
        print LOG "\n\n==> Trying to determine scanner ID\n";
    }
    my $scannerID = NeuroDB::MRI::findScannerID(
                                         $tarchiveInfo{
                                            'ScannerManufacturer'
                                         },
                                         $tarchiveInfo{'ScannerModel'},
                                         $tarchiveInfo{'ScannerSerialNumber'},
                                         $tarchiveInfo{
                                            'ScannerSoftwareVersion'
                                         },
                                         $centerID,\$dbh,$NewScanner
                                         );
    if($scannerID == 0) {
        if ($to_log) {
            $message = "\n ERROR: The ScannerID for this particular scanner does
                         not exist. Enable creating new ScannerIDs in your profile
                         or this archive can not be uploaded.\n\n";
            &writeErrorLog($logfile, $message, 88); exit 88;
            &writeErrorLog($logfile, $message, 88); exit 88;
        }
    }
    if ($to_log)  {
        print LOG "==> scanner ID : $scannerID\n\n";
    }
    return $scannerID;
}


sub determinPSC {

    my (%tarchiveinfo,$to_log) = @_;
    $to_log = 1 unless defined $to_log;
    my ($center_name, $centerID) =
    NeuroDB::MRI::getPSC(
                         $tarchiveInfo{$Settings::lookupCenterNameUsing},
                         \$dbh
                        );
    my $psc = $center_name;
    if ($to_log) {
        if (!$psc) {
            print LOG "\nERROR: No center found for this candidate \n\n";
            exit 77;
        }
        print LOG  "\n==> Verifying acquisition center\n -> Center Name  : 
                    $center_name\n -> CenterID     : $centerID\n";
    }
    return ($psc,$center_name, $centerID);
}

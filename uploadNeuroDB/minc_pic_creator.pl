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

my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.24 $ =~ /: (\d+)\.(\d+)/;
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
my $date        = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $debug       = 0;  
my $message     = '';
my $verbose     = 1;           # default for now
my $profile     = undef;       # this should never be set unless you are in a stable production environment

my $NewScanner  = 1;           # This should be the default unless you are a control freak
my $xlog        = 0;           # default should be 0
my $globArchiveLocation = 0;   # whether to use strict ArchiveLocation strings or to glob them (like '%Loc')
my $template         = "TarLoad-$hour-$min-XXXXXX"; # for tempdir
my ($PSCID, $md5sumArchive, $visitLabel, $gender);
my ($tarchive,%tarchiveInfo);
my $minc_path     = undef;       # the path/location of minc

my @opt_table = (
                 ["Basic options","section"],
                 ["-profile     ","string",1, \$profile, "name of config file in ~/.neurodb."],
                 ["-mincPath     ","string",1, \$minc_path, "name of config file in ~/.neurodb."],
                 ["Advanced options","section"],
                 ["-globLocation", "boolean", 1, \$globArchiveLocation,"Loosen the validity check of the tarchive allowing for the possibility that the tarchive was moved to a different directory."],
                 ["Fancy options","section"],
# fixme      ["-keeptmp", "boolean", 1, \$keep, "Keep temp dir. Makes sense if have infinite space on your server."],
                 ["-xlog", "boolean", 1, \$xlog, "Open an xterm with a tail on the current log file."],
                 );



my $Help = <<HELP;
***************************************************************************************
Dicom Validator 
***************************************************************************************

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


################################################################
######input option error checking###############################
################################################################
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if ($profile && !defined @Settings::db) { 
    print "\n\tERROR: You don't have a configuration file named 
           '$profile' in:  $ENV{HOME}/.neurodb/ \n\n"; 
    exit 33; 
}
if(!$ARGV[0] || !$profile) { 
    print $Help; 
    print "$Usage\n\tERROR: You must specify a valid tarchive
          and an existing profile.\n\n";
    exit 33;  }

my $tarchive = abs_path($ARGV[0]);
unless ((-e $tarchive) || (-e $minc_path)) {
    print "\nERROR: Either supply the path of the existing minc or the
             location of the tar to create the mincs.\n\n\n";
    exit 33;
}

if ($tarchive && $minc_path) {
    print "\n Cannot Supply both tarchive location and minc_path , choose one";
    exit 33;
}


################################################################
#######################initialization###########################
################################################################
################################################################
###########Create the Specific Log File#########################
################################################################
my $data_dir         = $Settings::data_dir;
my $TmpDir = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
my @temp     = split(/\//, $TmpDir);
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs"; if (!-d $LogDir) { mkdir($LogDir, 0700); }
my $logfile  = "$LogDir/$templog.log";
my $converter        = $Settings::converter;
my $pic_dir = $data_dir.'/pic';
my $mail_user        = $Settings::mail_user;
my $get_dicom_info   = $Settings::get_dicom_info;
my $exclude          = "localizer"; # case insensitive
my @minc_files = ();

print "logdir is $LogDir and logfile is $logfile \n";
open LOG, ">>", $logfile or die "Error Opening $logfile";
LOG->autoflush(1);

print LOG "testing";
# establish database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";


################################################################
#######################Construct the tarchiveinfo Array#########
################################################################
%tarchiveInfo = createTarchiveArray($tarchive,\$dbh,0);

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

################################################################
###################### Get the SessionID########################
################################################################

my ($sessionID, $requiresStaging) =
    NeuroDB::MRI::getSessionID(
        $subjectIDsref, $tarchiveInfo{'DateAcquired'},
         \$dbh, $subjectIDsref->{'subprojectID'}
    );

###############################################################
##############Extract the list of mincs from database##########
################Using tarchive path############################
###############################################################
@minc_files = getMincs($tarchive,\$dbh);

###############################################################
#####################Otherwise add the current minc path#######
########To the minc_files array if it is already set###########
###############################################################

print Dumper(@minc_files);
my $mcount = $#minc_files + 1;
print "\nNumber of MINC files that will be considered for inserting
      into the database: $mcount\n";
# If no good data was found stop processing and write error log.
if ($mcount < 1) {
    $message = "\nNo data could be converted into valid MINC files. 
                Localizers will not be considered! \n" ;
    print "Make sure the mincs are created \n";
    &writeErrorLog($logfile, $message, 99); 
    print $message; 
    exit 99;
}



################################################################
############################ LOOP through MINCs ################
################################################################
#At this step we actually have (multiple) MINC files so we loop#  
##a valid study has at least one file that can be uploaded######
################################################################

foreach my $minc (@minc_files)  {
    $minc =  $data_dir . "/" .$minc;
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
    ###at this point things will appear in the database#########
    #####Set some file information##############################
    ############################################################
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

    ############################################################
    ############remove the data_dir path from the variable######
    ############################################################
    my $file_path   =   $minc;
    $file_path      =~  s/$data_dir\///i;
    $file->setFileData('File', $file_path);
   
    ############################################################
    ###################make the browser pics####################
    ############################################################
    print "Making browser pics\n" if $verbose;
    &NeuroDB::MRI::make_pics(
        \$file, $data_dir, $pic_dir, $Settings::horizontalPics
    );
} # end foreach $minc



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





sub getMincs {
    my ($tarchive, $dbhr) = @_;
    $dbh = $$dbhr;
    my @mincLocations;

    
    my $where = "ArchiveLocation='$tarchive'";
    if ($globArchiveLocation) {
        $where = "ArchiveLocation LIKE '%/".basename($tarchive)."'";
    }
    
    ##This needs to be changed to using sourcearchive once it is added
    my $query = "SELECT f.File FROM files f 
                 JOIN tarchive t on (t.SessionID = f.SessionID)
                 WHERE $where";

    print $query. "\n";
    my $sth = $dbh->prepare($query); 
    $sth->execute();
    my @mincInfo;

    if ($sth->rows > 0) {
        while(my $mincInfo = $sth->fetchrow_array()) { 
            print $mincInfo . "\n";
            push @mincLocations, $mincInfo;
        }

    } else {
        $message = "\n ERROR: Only archived data can be uploaded. 
                    This seems not to be a valid archive for this study!\n\n";
        &writeErrorLog($logfile, $message, 77); 
        exit 77;
    }
   return @mincLocations;
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



sub determinSubjectID {
    my ($scannerID,%tarchiveinfo,$to_log) = @_;
    $to_log = 1 unless defined $to_log;

    if (!defined(&Settings::getSubjectIDs)) {
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
    if ($globArchiveLocation) {
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
        &writeErrorLog($logfile, $message, 77); 
        exit 77;
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
                        $tarchiveInfo{'ScannerManufacturer'},
                        $tarchiveInfo{'ScannerModel'},
                        $tarchiveInfo{'ScannerSerialNumber'},
                        $tarchiveInfo{'ScannerSoftwareVersion'},
                        $centerID,\$dbh,$NewScanner
                    );
    if ($scannerID == 0) {
        if ($to_log) {
            $message = "\n ERROR: The ScannerID for this particular scanner does
                         not exist. Enable creating new ScannerIDs in your profile
                         or this archive can not be uploaded.\n\n";
            &writeErrorLog($logfile, $message, 88); 
            exit 88;
            &writeErrorLog($logfile, $message, 88); 
            exit 88;
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

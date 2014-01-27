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
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
my $date        = sprintf(
                    "%4d-%02d-%02d %02d:%02d:%02d",
                    $year+1900,$mon+1,$mday,$hour,$min,$sec
                  );
my $debug       = 0;  
my $message     = '';
my $verbose     = 1;           # default for now
my $profile     = undef;       # this should never be set unless you are in a
                               # stable production environment
my $reckless    = 0;           # this is only for playing and testing. Don't
                               # set it to 1!!!

my $NewScanner  = 1;           # This should be the default unless you are a
                               # control freak
my $xlog        = 0;           # default should be 0
my $globArchiveLocation = 0;   # whether to use strict ArchiveLocation strings
                               # or to glob them (like '%Loc')
my $template         = "TarLoad-$hour-$min-XXXXXX"; # for tempdir
my ($PSCID, $md5sumArchive, $visitLabel, $gender);
my ($tarchive,%tarchiveInfo);
my $User             = `whoami`; 


my @opt_table = (
                 ["Basic options","section"],
                 ["-profile     ","string",1, \$profile,
                  "name of config file in ~/.neurodb."],

                 ["Advanced options","section"],
                 ["-reckless", "boolean", 1, \$reckless,
                  "Upload data to database even if study protocol is not
                   defined or violated."],
                 ["-globLocation", "boolean", 1, \$globArchiveLocation,
                  "Loosen the validity check of the tarchive allowing for
                  the possibility that the tarchive was moved to a
                  different directory."],
                 ["-newScanner", "boolean", 1, \$NewScanner, "By default a new 
                  scanner will be registered if the data you upload requires 
                  it. You can risk turning it off."],

                 ["Fancy options","section"],
# fixme      ["-keeptmp", "boolean", 1, \$keep, "Keep temp dir. Makes sense if
## have infinite space on your server."],
                 ["-xlog", "boolean", 1, \$xlog, "Open an xterm with a tail on
                  the current log file."],
                 );



my $Help = <<HELP;
******************************************************************************
Dicom Validator 
******************************************************************************

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
    configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n"; exit 33; 
}
if(!$ARGV[0] || !$profile) { 
    print $Help; 
    print "$Usage\n\tERROR: You must specify a valid tarchive and an existing
     profile.\n\n";  exit 33;  
}

my $tarchive = abs_path($ARGV[0]);
unless (-e $tarchive) {
    print "\nERROR: Could not find archive $tarchive. \nPlease, make sure the
     path to the archive is correct. Upload will exit now.\n\n\n";
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
my $LogDir   = "$data_dir/logs"; 
if (!-d $LogDir) { 
    mkdir($LogDir, 0700); 
}
my $logfile  = "$LogDir/$templog.log";
open LOG, ">>", $logfile or die "Error Opening $logfile";
LOG->autoflush(1);

print LOG "testing";
# establish database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";


%tarchiveInfo = createTarchiveArray($tarchive,\$dbh);
################################################################
################################################################
####STEP 1: Verify the archive using the checksum from database#
################################################################
################################################################
validateArchive($tarchive,%tarchiveInfo);
    
################################################################
################################################################
#######STEP 2: Verify PSC information using whatever field###### 
####contains####################################################
################################################################
################################################################

################################################################
################################################################
######the site string########################################### 
################################################################
################################################################
my ($psc,$center_name, $centerID) =determinPSC(%tarchiveInfo);


################################################################
################################################################
####STEP 3: Determine the ScannerID (optionally create a######## 
####new one if necessary)#######################################
################################################################
################################################################

my $scannerID = determinScannerID(%tarchiveInfo);


################################################################
################################################################
######STEP 4: Determine the subject identifiers#################
################################################################
################################################################

my $subjectIDsref = determinSubjectID($scannerID,%tarchiveInfo);

################################################################
################################################################
# ----- STEP 5: Optionally create candidates as needed##########
# Standardize gender (DICOM uses M/F, DB uses Male/Female)######
################################################################
################################################################

CreateMRICandidates($subjectIDsref,$gender,\%tarchiveInfo);

################################################################
################################################################
# ----- STEP 5a: Check the CandID/PSCID Match###################
# It's possible that the CandID exists, but doesn't match the### 
##PSCID. This will fail further down silently, so we explicitly#
# check that the data is correct here.##########################
################################################################
################################################################

my $query = "SELECT CandID, PSCID FROM candidate WHERE CandID=?";
my $logQuery = "INSERT INTO MRICandidateErrors (SeriesUID, TarchiveID, MincFile,
                 PatientName, Reason) VALUES (?, ?, ?, ?, ?)";
my $candlogSth = $dbh->prepare($logQuery);
my $sth = $dbh->prepare($query);
$sth->execute($subjectIDsref->{'CandID'});
my @CandIDCheck = $sth->fetchrow_array;
my $CandMismatchError;
if($sth->rows == 0) {
    print LOG  "\n\n => No candID";
    $CandMismatchError = 'CandID does not exist';
    exit 77;
}


$query = "SELECT CandID, PSCID FROM candidate WHERE PSCID=?";
$sth = $dbh->prepare($query);
$sth->execute($subjectIDsref->{'PSCID'});
if ($sth->rows == 0) {
    print LOG  "\n\n => No PSCID";
    $CandMismatchError= 'PSCID does not exist';
    exit 77;

}   

my @PSCIDCheck = $sth->fetchrow_array;

if($PSCIDCheck[0] != $CandIDCheck[0] || $PSCIDCheck[1] != $CandIDCheck[1]) {
    print LOG  "\n\n => CandID and PSCID mismatch";
    $CandMismatchError = 'CandID and PSCID do not match database';
     exit 77;

}

if ($subjectIDsref->{'isPhantom'}) {
    # CandID/PSCID errors don't apply to phantoms, so we don't want to trigger
    # the check which aborts the insertion
    $CandMismatchError = undef;
}

# ----- STEP 6: Get the SessionID
my ($sessionID, $requiresStaging) = 
    setMRISession($subjectIDsref, %tarchiveInfo);

# ----- STEP 7: extract the tarchive and feed the dicom data 
##dir to the uploader
my ($ExtractSuffix,$header,$study_dir) = extractAndParseTarchive($tarchive);

# optionally do extra filtering on the dicom data, if needed
if( defined( &Settings::dicomFilter )) {
    Settings::dicomFilter($study_dir, \%tarchiveInfo);
}

# ----- STEP 8: Now we know that we actually have data and more things have to
## happen so let get started:

# make the notifier object
my $notifier = NeuroDB::Notify->new(\$dbh);


################################################################
################################################################
##############Set the isValid to true###########################
################################################################
my $where = "WHERE ArchiveLocation='$tarchive'";
if($globArchiveLocation) {
     $where = "WHERE ArchiveLocation LIKE '%/".basename($tarchive)."'";
}

$query = "UPDATE tarchive SET IsValidated='1' ";
$query = $query . $where;
$dbh->do($query);


sub determinPSC {
    my (%tarchiveinfo) = @_;
    my ($center_name, $centerID) = 
    NeuroDB::MRI::getPSC(
        $tarchiveInfo{$Settings::lookupCenterNameUsing},
        \$dbh
    );
    my $psc = $center_name;
    if (!$psc) { 
        print LOG "\nERROR: No center found for this candidate \n\n"; 
        exit 77; 
    }
    print LOG  "\n==> Verifying acquisition center\n -> Center Name  : 
                $center_name\n -> CenterID     : $centerID\n";
    return ($psc,$center_name, $centerID);
}

sub validateArchive{
    my ($tarchive,%tarchiveinfo) = @_;
      ##my (%tarchiveinfo) = %{$_[0]};
    print LOG  "\n==> verifying dicom archive md5sum (checksum)\n";
    my $md5_check = `md5sum $tarchive`;
    my ($md5_real, $real) = split(' ', $md5_check);
    my ($md5_db  , $db)   = split(' ', $tarchiveinfo{'md5sumArchive'});
    print LOG " -> checksum for target        :  $md5_real\n -> checksum 
                from database     :  $md5_db\n";
    
    if ($md5_real ne $md5_db) {
        $message =  "\nerror: archive seems to be corrupted or modified. upload
                     will exit now.\nplease read the creation logs for more
                     information!\n\n";
        &writeErrorLog($logfile, $message, 77); exit 77;
    }
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

    if ($scannerID == 0) {
        if ($to_log) {
            $message = "\n ERROR: The ScannerID for this particular scanner does
                         not exist. Enable creating new ScannerIDs in your profile
                         or this archive can not be uploaded.\n\n";
            &writeErrorLog($logfile, $message, 88); exit 88;
            &writeErrorLog($logfile, $message, 88); exit 88;
        }
    }
    if ($to_log) {
        print LOG "==> scanner ID : $scannerID\n\n";
    }
    return $scannerID;
}


sub determinSubjectID {
    my ($scannerID,%tarchiveinfo) = @_;

    if(!defined(&Settings::getSubjectIDs)) {
        $message =  "\nERROR: Profile does not contain getSubjectIDs routine.
                     Upload will exit now.\n\n";
        &writeErrorLog($logfile, $message, 66); exit 66;
    }
    my $subjectIDsref = Settings::getSubjectIDs($tarchiveInfo{'PatientName'},
                                            $tarchiveInfo{'PatientID'},
                                            $scannerID,
                                            \$dbh);
    print LOG "\n==> Data found for candidate   : $subjectIDsref->{'CandID'} 
              - $subjectIDsref->{'PSCID'} - Visit: 
              $subjectIDsref->{'visitLabel'} - Acquired :
              $tarchiveInfo{'DateAcquired'}\n";
    return $subjectIDsref;
}

sub extractAndParseTarchive{
    my ($tarchive) = @_;

    my $study_dir = $TmpDir . "/" . extract_tarchive($tarchive, $TmpDir);
    my $ExtractSuffix  = basename($tarchive, ".tar");
    # get rid of the tarchive Prefix 
    $ExtractSuffix =~ s/DCM_(\d){4}-(\d){2}-(\d){2}_//;
    my $info      = "head -n 12 ${TmpDir}/${ExtractSuffix}.meta";
    my $header    = `$info`;
    print LOG "\n$header\n";
    return ($ExtractSuffix,$study_dir,$header);
}




# Most important function now. Gets the tarchive and extracts it so data can
## actually be uploaded
sub setMRISession {
    my ($subjectIDsref, %tarchiveInfo) = @_;
    # This will actually create a visit count if it is not provided through the
    # IDs in the dicom header
    # The count starts with 1 if there is none.
    if(!defined($subjectIDsref->{'visitLabel'})) { 
        $subjectIDsref->{'visitLabel'} = 
        lookupNextVisitLabel($$subjectIDsref->{'CandID'}, \$dbh); 
    }

    # get session ID
    print LOG "\n\n==> Getting session ID\n";
    my ($sessionID, $requiresStaging) = 
        NeuroDB::MRI::getSessionID(
            $subjectIDsref, $tarchiveInfo{'DateAcquired'
            }, \$dbh, $subjectIDsref->{'subprojectID'}
        );

    # Retain session ID for tarchive table    
    print LOG "    SessionID: $sessionID\n";    # Staging: $requiresStaging\n";

    # Make sure MRI Scan Done is set to yes, because now there is data.
    if ($sessionID) {
        $query = "UPDATE session SET Scan_done='Y' WHERE ID=$sessionID";
        $dbh->do($query);
    }
    return ($sessionID, $requiresStaging);
}


sub logHeader () {
    print LOG "
-------------------------------------------------------------------------------
                                     AUTOMATED DICOM DATA UPLOAD
-------------------------------------------------------------------------------
*** Date and time of upload    : $date
*** Location of source data    : $tarchive
*** tmp dir location           : $TmpDir
";

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

# Most important function now. Gets the tarchive and extracts it so data can
## actually be uploaded
sub extract_tarchive {
    my ($tarchive, $tempdir) = @_;
    print "Extracting tarchive\n" if $verbose;
    `cd $tempdir ; tar -xf $tarchive`;
    opendir TMPDIR, $tempdir;
    my @tars = grep { /\.tar\.gz$/ && -f "$tempdir/$_" } readdir(TMPDIR);
    closedir TMPDIR;
    if(scalar(@tars) != 1) {
        print "Error: Could not find inner tar in $tarchive!\n";
        print @tars . "\n";
        exit(1);
    }
    my $dcmtar = $tars[0];
    my $dcmdir = $dcmtar;
    $dcmdir =~ s/\.tar\.gz$//;
    
    `cd $tempdir ; tar -xzf $dcmtar`;
    return $dcmdir;
}



# this is a useful function that will close the log and write error messages
# in case of abnormal program termination
sub writeErrorLog {
    my ($logfile, $message, $failStatus, ) = @_;
    print LOG $message;
    print LOG "program exit status: $failStatus";
    `cat $logfile >> $LogDir/error.log`;
    close LOG;
    `rm -f $logfile`;
}


sub CreateMRICandidates {
    # Standardize gender (DICOM uses M/F, DB uses Male/Female)

    my ($subjectIDsref,$gender,%tarchiveinfo) = @_;

    if ($tarchiveInfo{'PatientGender'} eq 'F') {
            $gender = "Female";
    } elsif ($tarchiveInfo{'PatientGender'} eq 'M') {
        $gender = "Male";
    }

    # Create non-existent candidate if the profile allows for candidate creation
    if (!NeuroDB::MRI::subjectIDExists($subjectIDsref->{'CandID'}, \$dbh)
        && $Settings::createCandidates) {
            chomp($User);
            $subjectIDsref->{'CandID'} = NeuroDB::MRI::createNewCandID(\$dbh);
            $query = "INSERT INTO candidate (CandID, PSCID, DoB, Gender,
                      CenterID, Date_active, Date_registered, UserID,
                      Entity_type) VALUES (" .
            $dbh->quote(
                $subjectIDsref->{'CandID'}
            ).",".
            $dbh->quote(
                $subjectIDsref->{'PSCID'}
            ).",".
            $dbh->quote(
                $tarchiveInfo{'PatientDoB'}
            ) ."," .
            $dbh->quote($gender).",". $dbh->quote($centerID). ", NOW(), NOW(),
               '$User', 'Human')";
            $dbh->do($query);
            print LOG  "\n==> CREATED NEW CANDIDATE :
            $subjectIDsref->{'CandID'}";
    } elsif ($subjectIDsref->{'CandID'}) {# if the candidate exis
        print LOG  "\n==> getSubjectIDs returned this CandID/DCCID :
        $subjectIDsref->{'CandID'}\n";
    } else {
        $message = "\n ERROR: The candidate could not be considered for 
                    uploading, since s/he is not registered in your database.
                     \n" .
                    " The dicom header PatientID is   : 
                    $tarchiveInfo{'PatientID'}\n".
                    " The dicom header PatientName is : 
                    $tarchiveInfo{'PatientName'}\n\n";
        &writeErrorLog($logfile, $message, 66); exit 66;
    }
}


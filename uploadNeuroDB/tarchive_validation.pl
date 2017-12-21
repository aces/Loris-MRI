#! /usr/bin/perl

=pod

=head1 NAME

tarchive_validation.pl -- Validates the tarchive against the one inserted in
the LORIS database.

=head1 SYNOPSIS

perl tarchive_validation.pl C<[options]>

Available options are:

-profile     : name of the config file in ../dicom-archive/.loris-mri

-reckless    : upload data to the database even if the study protocol
                is not defined or if it is violated

-globLocation: loosen the validity check of the tarchive allowing for
                the possibility that the tarchive was moved to a
                different directory

-newScanner  : boolean, if set, register new scanners into the database

-verbose     : boolean, if set, run the script in verbose mode

=head1 DESCRIPTION

The program does the following validations:

- Verification of the DICOM study archive given as an argument to the script
using the checksum from the one inserted in the database

- Verification of the PSC information using whatever field containing the site
string (typically, the patient name or patient ID)

- Verification/determination of the ScannerID of the DICOM study archive
(optionally creates a new scanner entry in the database if necessary)

- Optionally, creation of candidates as needed and standardization of gender
information when creating the candidates (DICOM uses M/F, LORIS database uses
Male/Female)

- Check of the CandID/PSCID match. It's possible that the CandID exists, but
that CandID and PSCID does not correspond to the same candidate. This would
fail further down silently, so we explicitly check that this information is
correct here.

- Validation/Obtention of the SessionID

- Optionally, completion of extra filtering on the DICOM dataset, if needed

- Finally, the C<isTarchiveValidated> field in the C<mri_upload> table is set
to C<TRUE>

=head2 Methods


=cut


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
################################################################
# These are the NeuroDB modules to be used #####################
################################################################
use lib "$FindBin::Bin";
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::Notify;
use NeuroDB::MRIProcessingUtility;

my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.24 $ 
                =~ /: (\d+)\.(\d+)/;
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
my $date        = sprintf(
                    "%4d-%02d-%02d %02d:%02d:%02d",
                    $year+1900,$mon+1,$mday,$hour,$min,$sec
                  );
my $debug       = 0 ;  
my $where       = '';
my $sth         = undef;
my $query       = '';
my $message     = '';
my $verbose     = 0;           # default, overwritten if scripts are run with -verbose
my $profile     = undef;       # this should never be set unless you are in a
                               # stable production environment
my $reckless    = 0;           # this is only for playing and testing. Don't
                               # set it to 1!!!
my $NewScanner  = 1;           # This should be the default unless you are a
                               # control freak
my $globArchiveLocation = 0;   # whether to use strict ArchiveLocation strings
                               # or to glob them (like '%Loc')
my $template         = "TarLoad-$hour-$min-XXXXXX"; # for tempdir
my ($gender, $tarchive,%tarchiveInfo);
my $User             = `whoami`; 

my @opt_table = (
                 ["Basic options","section"],
                 ["-profile","string",1, \$profile,
                  "name of config file in ../dicom-archive/.loris_mri"],
                 ["Advanced options","section"],
                 ["-reckless", "boolean", 1, \$reckless,
                  "Upload data to database even if study protocol is not".
                  " defined or violated."],
                 ["-globLocation", "boolean", 1, \$globArchiveLocation,
                  "Loosen the validity check of the tarchive allowing for".
                  " the possibility that the tarchive was moved to a". 
                  " different directory."],
                 ["-newScanner", "boolean", 1, \$NewScanner, "By default a". 
                  " new scanner will be registered if the data you upload".
                  " requires it. You can risk turning it off."],

                 ["Fancy options","section"],

                 ["General options","section"],
                 ["-verbose", "boolean", 1, \$verbose, "Be verbose."],

                 );

my $Help = <<HELP;
******************************************************************************
Dicom Validator 
******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo

The program does the following validation


- Verify the archive using the checksum from database

- Verify PSC information using whatever field contains site string

- Verify/determine the ScannerID (optionally create a new one if necessary)

- Optionally create candidates as needed Standardize gender (DICOM uses M/F, 
  DB uses Male/Female)

- Check the CandID/PSCID Match It's possible that the CandID exists, but 
  doesn't match the PSCID. This will fail further
  down silently, so we explicitly check that the data is correct here.

- Validate/Get the SessionID

- Optionally do extra filtering on the dicom data, if needed

- Finally the isTarchiveValidated is set true in the MRI_Upload table

HELP
my $Usage = <<USAGE;
usage: $0 </path/to/DICOM-tarchive> [options]
       $0 -help to list options
USAGE
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;

################################################################
############### input option error checking ####################
################################################################
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ($profile && !@Settings::db) { 
    print "\n\tERROR: You don't have a 
    configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; 
    exit 2; 
}
if (!$ARGV[0] || !$profile) { 
    print $Help; 
    print "$Usage\n\tERROR: You must specify a valid tarchive and an existing ".
          "profile.\n\n";  
    exit 3;  
}
$tarchive = abs_path($ARGV[0]);
unless (-e $tarchive) {
    print "\nERROR: Could not find archive $tarchive. \nPlease, make sure ".
           "the path to the archive is correct. Upload will exit now.\n\n\n";
    exit 4;
}

################################################################
########## initialization ######################################

################################################################
################ Establish database connection #################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

################################################################
########## Create the Specific Log File ########################
################################################################
my $data_dir = NeuroDB::DBI::getConfigSetting(
                    \$dbh,'dataDirBasepath'
                    );
my $TmpDir = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
my @temp     = split(/\//, $TmpDir);
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs"; 
if (!-d $LogDir) { 
    mkdir($LogDir, 0770); 
}
my $logfile  = "$LogDir/$templog.log";
open LOG, ">>", $logfile or die "Error Opening $logfile";
LOG->autoflush(1);
&logHeader();

print LOG "\n==> Successfully connected to database \n";

################################################################
################ MRIProcessingUtility object ###################
################################################################
my $utility = NeuroDB::MRIProcessingUtility->new(
                  \$dbh,$debug,$TmpDir,$logfile,
                  $verbose
              );

################################################################
############### Create tarchive array ##########################
################################################################
################################################################
my $tarchiveLibraryDir = NeuroDB::DBI::getConfigSetting(
                       \$dbh,'tarchiveLibraryDir'
                       );
$tarchiveLibraryDir    =~ s/\/$//g;
my $ArchiveLocation    = $tarchive;
$ArchiveLocation       =~ s/$tarchiveLibraryDir\/?//g;
%tarchiveInfo = $utility->createTarchiveArray(
                    $ArchiveLocation,
                    $globArchiveLocation
                );

################################################################
############### Get the tarchive-id ############################
################################################################
$where = "WHERE TarchiveID=?";
$query = "SELECT COUNT(*) FROM mri_upload $where ";
$sth = $dbh->prepare($query);
$sth->execute($tarchiveInfo{TarchiveID});
my $tarchiveid_count = $sth->fetchrow_array;

################################################################
### Insert into the mri_upload table correct values ############
### only if the $tarchive_id doesn't exist 
################################################################

if ($tarchiveid_count==0)  {
    ############################################################	
    ##if the scan is already inserted into the mri_upload ######
    ###update it################################################
    ############################################################
    $where = "WHERE DecompressedLocation=?";
    $query = "SELECT COUNT(*) FROM mri_upload $where ";
    $sth = $dbh->prepare($query);
    $sth->execute($tarchiveInfo{SourceLocation});
    my $source_location = $sth->fetchrow_array;
    if ($source_location !=0) {
    	$where = "WHERE DecompressedLocation=?";
	$query = "UPDATE mri_upload SET TarchiveID=? ";
	$query = $query . $where;
	my $mri_upload_update = $dbh->prepare($query);
	$mri_upload_update->execute($tarchiveInfo{'SourceLocation'},
				    $tarchiveInfo{TarchiveID}
				   );
    } else {
       #########################################################
       ##otherwise insert it####################################
       #########################################################
       $query = "INSERT INTO mri_upload (UploadedBy, ".
                "UploadDate,TarchiveID, DecompressedLocation)" .
                " VALUES (?,now(),?,?)";
       my $mri_upload_inserts = $dbh->prepare($query);
       $mri_upload_inserts->execute(
           $User,
           $tarchiveInfo{TarchiveID},
           $tarchiveInfo{'SourceLocation'}
       );
    }
}
################################################################
#### Verify the archive using the checksum from database #######
################################################################
################################################################
$utility->validateArchive($tarchive,\%tarchiveInfo);

################################################################
### Verify PSC information using whatever field ################ 
### contains site string #######################################
################################################################
my ($center_name, $centerID) =
    $utility->determinePSC(\%tarchiveInfo,1);

################################################################
################################################################
### Determine the ScannerID (optionally create a ############### 
### new one if necessary) ######################################
################################################################
################################################################
my $scannerID = $utility->determineScannerID(
                    \%tarchiveInfo,1,
                    $centerID,$NewScanner
                );

################################################################
################################################################
##### Determine the subject identifiers ########################
################################################################
################################################################
my $subjectIDsref = $utility->determineSubjectID(
                        $scannerID,\%tarchiveInfo,1
                    );

################################################################
################################################################
## Optionally create candidates as needed Standardize gender ###
## (DICOM uses M/F, DB uses Male/Female) #######################
################################################################
################################################################
$utility->CreateMRICandidates(
    $subjectIDsref,$gender,
    \%tarchiveInfo,$User,
    $centerID
);

################################################################
################################################################
## Check the CandID/PSCID Match It's possible that the CandID ## 
## exists, but doesn't match the PSCID. This will fail further #
## down silently, so we explicitly check that the data is ######
## correct here. ###############################################
################################################################
################################################################
my $CandMismatchError= $utility->validateCandidate(
				$subjectIDsref,
				$tarchiveInfo{'SourceLocation'});
if (defined $CandMismatchError) {
    print "$CandMismatchError \n";
    ##Note that the script will not exit, so that further down
    ##it can be inserted per minc into the MRICandidateErrors
}
################################################################
############ Get the SessionID #################################
################################################################
my ($sessionID, $requiresStaging) = 
    $utility->setMRISession($subjectIDsref, \%tarchiveInfo);

################################################################
### Extract the tarchive and feed the dicom data dir to ######## 
### The uploader ###############################################
################################################################
my ($ExtractSuffix,$study_dir,$header) = 
    $utility->extractAndParseTarchive(
                $tarchive, $tarchiveInfo{'SourceLocation'});

################################################################
# Optionally do extra filtering on the dicom data, if needed ###
################################################################
if ( defined( &Settings::dicomFilter )) {
    Settings::dicomFilter($study_dir, \%tarchiveInfo);
}

################################################################
##Update the IsTarchiveValidated flag in the mri_upload table ##
################################################################
$where = "WHERE TarchiveID=?";
$query = "UPDATE mri_upload SET IsTarchiveValidated='1' ";
$query = $query . $where;
my $mri_upload_update = $dbh->prepare($query);
$mri_upload_update->execute($tarchiveInfo{TarchiveID});


exit 0;

=pod

=head3 logHeader()

Creates and prints the LOG header.

=cut

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

__END__


=pod

=head1 TO DO

Nothing planned.

=head1 BUGS

None reported.

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut


#!/usr/bin/perl -w
# Zia Mohades 2014
# zia.mohades@mcgill.ca
# Perl tool to update the mri_upload table

use strict;

use constant GET_COUNT    => 1;

use Cwd qw/ abs_path /;
use File::Basename qw/ dirname /;
use File::Find;
use File::Temp qw/ tempdir /;
use FindBin;
use Getopt::Tabular;
use File::Basename;
use lib "$FindBin::Bin";
use DICOM::DICOM;

use NeuroDB::Database;
use NeuroDB::DatabaseException;

use NeuroDB::objectBroker::ObjectBrokerException;
use NeuroDB::objectBroker::ConfigOB;
use NeuroDB::objectBroker::TarchiveOB;
use NeuroDB::objectBroker::MriUploadOB;

use TryCatch;

use DateTime;

my $verbose = 0;
my $profile    = undef;
my $source_location = '';
my $tarchive = '';
my $query = '';
my $sth = undef;
my $User             = `whoami`;
chomp $User;
my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.24 $
    =~ /: (\d+)\.(\d+)/;


my $globArchiveLocation = 0;             # whether to use strict ArchiveLocation strings
                                         # or to glob them (like '%Loc')

my $Help = <<HELP;
*******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo


This program does the following:

- Updates the mri_upload table to populate the fields/columns:
   UploadedBy,UploadDate,TarchiveID and SourceLocation


HELP

my $Usage = "------------------------------------------
$0 updates the mri_upload table to populate the fields

Usage:\n\t $0 -profile <profile>
\n\n See $0 -help for more info\n\n";

my @arg_table =
	 (
	  ["Main options", "section"],
	  ["-profile","string",1, \$profile, "Specify the name of the config file
          which resides in .loris_mri in the current directory."],
	  ["-verbose", "boolean", 1, \$verbose, "Be verbose."],
      ["-globLocation", "boolean", 1, \$globArchiveLocation, "Loosen the".
       " validity check of the tarchive allowing for the possibility that".
       " the tarchive was moved to a different directory."],
      ["-sourceLocation", "string", 1, \$source_location, "The location".
       " where the uploaded file exists."],
      ["-tarchivePath","string",1, \$tarchive, "The absolute path to".
       " tarchive-file"]
    );

# Parse arguments
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@arg_table, \@ARGV) || exit 1;

################################################################
################# checking for profile settings#################
################################################################
if (-f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
	{ 
        package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" 
    }
}

if ($profile && !@Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:
            $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; 
    exit 2;
} 

################################################################
################# if profile not specified######################
################################################################
if(!$profile) { 
    print $Usage; print "\n\tERROR: You must specify an existing profile.\n\n";  
    exit 3;  
}

################################################################
################# if tarchive not specified#####################
################################################################
unless (-e $tarchive) {
    print "\nERROR: Could not find archive $tarchive. \nPlease, make sure the 
            path to the archive is correct. Upload will exit now.\n\n\n";
    exit 4;
}

################################################################
#################if the sourcelocation is not set###############
################################################################
unless (-e $source_location) {
    print "\nERROR: Could not find sourcelocation $source_location \nPlease,
           make sure the sourcelocation is correct. Upload will 
           exit now.\n\n\n";
    exit 5;
}
################################################################
#####establish database connection if database option is set####
################################################################
print "Connecting to database.\n" if $verbose;
my $db = NeuroDB::Database->new(
    databaseName => $Settings::db[0],
    userName     => $Settings::db[1],
    password     => $Settings::db[2],
    hostName     => $Settings::db[3]
);
$db->connect();

################################################################
#####check to see if the tarchiveid is already set or not#######
######if it's already in the mri_upload table then it will######
######generate an error#########################################
################################################################

# fetch tarchiveLibraryDir from ConfigSettings in the database

my $configOB = NeuroDB::objectBroker::ConfigOB->new(db => $db);
my $tarchiveLibraryDir = $configOB->getTarchiveLibraryDir();

# determine tarchive path stored in the database (without tarchiveLibraryDir)
my $tarchive_path = $tarchive;
$tarchive_path    =~ s/$tarchiveLibraryDir\/?//g;

# Check if there is already an mri upload record for the tarchive
my $mriUploadOB = NeuroDB::objectBroker::MriUploadOB->new(db => $db);
my $resultRef = $mriUploadOB->getWithTarchive(
    GET_COUNT, $tarchive_path, $globArchiveLocation
);

if($resultRef->[0]->[0] > 0) {
   print "\n\tERROR: the tarchive is already uploaded \n\n";
   exit 6;
}

################################################################
#####get the tarchiveid from tarchive table#####################
################################################################

my $tarchiveOB = NeuroDB::objectBroker::TarchiveOB->new(db => $db);
$resultRef = $tarchiveOB->getByTarchiveLocation(
    ['TarchiveID'], $tarchive_path, $globArchiveLocation
);

if(@$resultRef != 1) {
    die sprintf(
        "Unexpected number of tarchive records with location %s found: %d\n",
        $tarchive_path,
        scalar(@$resultRef)
    );
}
my $tarchiveID = $resultRef->[0]->[0];

################################################################
 #####populate the mri_upload columns with the correct values####
################################################################

$mriUploadOB->insert(
    {
      UploadedBy           => $User,
      UploadDate           => DateTime->now()->strftime('%Y-%m-%d %H:%M:%S'),
      TarchiveID           => $tarchiveID,
      DecompressedLocation => $source_location
    }
);

print "Done updateMRI_upload.pl execution!\n" if $verbose;
exit 0;

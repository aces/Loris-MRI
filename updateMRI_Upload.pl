#!/usr/bin/perl 
# Zia Mohades 2014
# zia.mohaes@mcgill.ca
# Perl tool to update the mri_upload table

use strict;

use Cwd qw/ abs_path /;
use File::Basename qw/ dirname /;
use File::Find;
use File::Temp qw/ tempdir /;
use FindBin;
use Getopt::Tabular;
use File::Basename;
use lib "$FindBin::Bin";
use DICOM::DICOM;
use DB::DBI;

my $verbose = 0;
my $profile    = undef;
my $source_location = '';
my $tarchive = '';
my $query = '';
my $tarchiveID = 0;
my $User             = `whoami`;
my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.24 $
    =~ /: (\d+)\.(\d+)/;


my $globArchiveLocation = 0;   # whether to use strict ArchiveLocation strings
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
          which resides in .neurodb in your home directory."],
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
if (-f "$ENV{HOME}/.neurodb/$profile") {
	{ 
        package Settings; do "$ENV{HOME}/.neurodb/$profile" 
    }
}

if ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:
            $ENV{HOME}/.neurodb/ \n\n"; 
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
my $dbh = &DB::DBI::connect_to_db(@Settings::db); 
print "Connecting to database.\n" if $verbose;

################################################################
#####check to see if the tarchiveid is already set or not#######
################################################################
my $where = " WHERE t.ArchiveLocation = '$tarchive'";
if ($globArchiveLocation) {
    $where = " WHERE t.ArchiveLocation LIKE '%/".basename($tarchive)."'";
}
$query  = "SELECT COUNT(*) FROM mri_upload m
                        JOIN tarchive t on (t.TarchiveID=m.TarchiveID) $where";
my $count = $dbh->selectrow_array($query);
if($count>0) {
   print "\n\tERROR: the tarchive is already uploaded \n\n"; 
   exit 6;
} 


################################################################
#####get the tarchiveid from tarchive table#####################
################################################################
my $where = " WHERE ArchiveLocation = '$tarchive'";
if ($globArchiveLocation) {
    $where = " WHERE ArchiveLocation LIKE '%/".basename($tarchive)."'";
}   
$query = "SELECT TarchiveID FROM tarchive $where ";
my $tarchiveID = $dbh->selectrow_array($query);


################################################################
 #####populate the mri_upload columns with the correct values####
################################################################
$query = "INSERT INTO mri_upload SET UploadedBy='$User', UploadDate=NOW() ,". 
         " TarchiveID ='$tarchiveID' , SourceLocation='$source_location'";
$dbh->do($query);

print "Done!\n";
exit 0;

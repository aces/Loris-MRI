#!/usr/bin/perl 
# Zia Mohades 2014
# zia.mohades@mcgill.ca
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
my $sth = undef;
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
my $dbh = &DB::DBI::connect_to_db(@Settings::db); 
print "Connecting to database.\n" if $verbose;

################################################################
#####check to see if the tarchiveid is already set or not#######
######if it's already in the mri_upload table then it will######
######generate an error#########################################
################################################################

# fetch tarchiveLibraryDir from ConfigSettings in the database
my $tarchiveLibraryDir = &DB::DBI::getConfigSetting(
                            \$dbh,'tarchiveLibraryDir'
                            );
# determine tarchive path stored in the database (without tarchiveLibraryDir)
my $tarchive_path = $tarchive;
$tarchive_path    =~ s/$tarchiveLibraryDir\/?//g;  

my $where         = " WHERE t.ArchiveLocation =?";

if ($globArchiveLocation) {
    $where = " WHERE t.ArchiveLocation LIKE ?";
    $tarchive_path = basename($tarchive);
}

($query = <<QUERY) =~ s/\n/ /gm;
SELECT 
  COUNT(*) 
FROM 
  mri_upload m 
JOIN 
  tarchive t ON (t.TarchiveID=m.TarchiveID) 
QUERY
$query .= $where;
$sth = $dbh->prepare($query);
$sth->execute($tarchive_path);
my $count = $sth->fetchrow_array;
if($count>0) {
   print "\n\tERROR: the tarchive is already uploaded \n\n"; 
   exit 6;
} 


################################################################
#####get the tarchiveid from tarchive table#####################
################################################################
($query = <<QUERY) =~ s/\n/ /gm;
SELECT 
  t.TarchiveID 
FROM 
  tarchive t 
QUERY
$query .= $where;
$sth = $dbh->prepare($query);
$sth->execute("%".$tarchive_path."%");
my $tarchiveID = $sth->fetchrow_array;


################################################################
 #####populate the mri_upload columns with the correct values####
################################################################
($query = <<QUERY) =~ s/\n/ /gm;
INSERT INTO mri_upload 
  (UploadedBy, UploadDate, TarchiveID, DecompressedLocation) 
VALUES
  (?, now(), ?, ?)
QUERY
my $mri_upload_insert = $dbh->prepare($query);
$mri_upload_insert->execute($User,$tarchiveID,$source_location);

print "Done updateMRI_upload.pl execution!\n" if $verbose;
exit 0;

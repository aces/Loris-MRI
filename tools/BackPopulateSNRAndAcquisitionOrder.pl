#! /usr/bin/perl

use strict;
use warnings;
use Getopt::Tabular;
use File::Temp qw/ tempdir /;
use File::Basename;
use File::Find;
use Cwd;
use NeuroDB::DBI;
use NeuroDB::MRIProcessingUtility;

use NeuroDB::Database;

my $verbose = 1;
my $debug = 1;
my $profile = undef;
my $TarchiveID = undef;
my $query;

my @opt_table = (
    [ "-profile", "string", 1, \$profile,
      "name of config file in ../dicom-archive/.loris_mri"
    ],
    [ "-tarchive_id", "string", 1, \$TarchiveID,
      "tarchive_id of the .tar to be processed from tarchive table"
    ]
); 

my $Help = <<HELP;

This script will back populate the files table with entries for 
the AcqOrderPerModality column; in reference to: 
https://github.com/aces/Loris-MRI/pull/160
as well as populate the parameter_file table with SNR entries 
in reference to: https://github.com/aces/Loris-MRI/pull/142
It can take in tarchiveID as an argument if only a specific .tar is to be 
processed; otherwise, all .tar in the tarchive tables are processed.
HELP

my $Usage = <<USAGE;

Usage: $0 -help to list options

USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;

################################################################
################### input option error checking ################
################################################################
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ($profile && !@Settings::db) {
    print "\n\tERROR: You don't have a configuration file named ".
          "'$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit 2;
}

################################################################
######### Establish database connection ########################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

my $db = NeuroDB::Database->new(
    databaseName => $Settings::db[0],
    userName     => $Settings::db[1],
    password     => $Settings::db[2],
    hostName     => $Settings::db[3]
);
$db->connect();
print "\nSuccessfully connected to database \n";

################################################################
######### Initialize variables #################################
################################################################
my $data_dir = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'dataDirBasepath'
                    );
my $tarchiveLibraryDir = &NeuroDB::DBI::getConfigSetting(
                       \$dbh,'tarchiveLibraryDir'
                       );
$tarchiveLibraryDir    =~ s/\/$//g;
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) 
    =localtime(time);
my $template = "TarLoad-$hour-$min-XXXXXX"; # for tempdir
my $TmpDir = tempdir(
                 $template, TMPDIR => 1, CLEANUP => 1 
             );
my @temp     = split(/\//, $TmpDir); 
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs"; 
if (!-d $LogDir) { 
    mkdir($LogDir, 0770); 
}
my $logfile  = "$LogDir/$templog.log";

################################################################
################## Instantiate MRIProcessingUtility ############
################################################################
my $utility = NeuroDB::MRIProcessingUtility->new(
                  $db, \$dbh,$debug,$TmpDir,$logfile,
                  $LogDir,$verbose
              );

################################################################
# Grep tarchive list for all those entries with         ########
# NULL in ArchiveLocationPerModality                    ########
################################################################

# Query to grep all tarchive entries
if (!defined($TarchiveID)) {
    $query = "SELECT TarchiveID, ArchiveLocation " .
        "FROM tarchive";
}
# Selecting tarchiveID is redundant here but it makes the while() loop
# applicable to both cases; when a TarchiveID is specified or not
else {
    $query = "SELECT TarchiveID, ArchiveLocation " .
        "FROM tarchive ".
        "WHERE TarchiveID = $TarchiveID ";
}

my $sth = $dbh->prepare($query);
$sth->execute();
    
if($sth->rows > 0) {
	# Create tarchive list hash with old and new location
    while ( my $rowhr = $sth->fetchrow_hashref()) {    
        my $TarchiveID = $rowhr->{'TarchiveID'};
        my $ArchLoc    = $rowhr->{'ArchiveLocation'};
		print "Currently updating the SNR for applicable files in parameter_file table ".
            "for tarchiveID $TarchiveID at location $ArchLoc\n";    
        $utility->computeSNR($TarchiveID, $ArchLoc, $profile);
		print "Currently updating the Acquisition Order per modality in files table\n";    
        $utility->orderModalitiesByAcq($TarchiveID, $ArchLoc);

		print "Finished updating back-populating SNR and Acquisition Order ".
            "per modality for TarchiveID $TarchiveID \n";
	}
}
else {
	print "No tarchives to be updated \n";	
}

$dbh->disconnect();
exit 0;

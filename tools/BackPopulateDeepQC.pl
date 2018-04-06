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

This script will back populate the parameter_file table with DeepQC entries.
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
                  \$dbh,$debug,$TmpDir,$logfile,
                  $LogDir,$verbose
              );

################################################################
# Grep tarchive list for all those entries with         ########
# NULL in ArchiveLocationPerModality                    ########
################################################################

# Query to grep all tarchive entries
if (!defined($TarchiveID)) {
    $query = "SELECT TarchiveID " .
        "FROM tarchive";
}
# Selecting tarchiveID is redundant here but it makes the while() loop
# applicable to both cases; when a TarchiveID is specified or not
else {
    $query = "SELECT TarchiveID " .
        "FROM tarchive ".
        "WHERE TarchiveID = $TarchiveID ";
}

my $sth = $dbh->prepare($query);
$sth->execute();

if($sth->rows > 0) {
	# Create tarchive list hash with old and new location
    while ( my $rowhr = $sth->fetchrow_hashref()) {
        my $TarchiveID = $rowhr->{'TarchiveID'};
		print "Currently updating the DeepQC for applicable files in parameter_file table ".
            "for tarchiveID $TarchiveID\n";
        $utility->computeDeepQC($TarchiveID, $profile);
		print "Finished updating DeepQC for for TarchiveID $TarchiveID\n";
	}
}
else {
	print "No tarchives to be updated \n";
}

$dbh->disconnect();
exit 0;

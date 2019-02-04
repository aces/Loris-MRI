#!/usr/bin/perl -w
# Zia Mohades 2014
# zia.mohades@mcgill.ca
# Perl tool to update the mri_upload table

=pod

=head1 NAME

updateMRI_Upload.pl - updates database table C<mri_upload> according to an entry in table
   C<tarchive>.

=head1 SYNOPSIS

updateMRI_Upload.pl [options] -profile prod -tarchivePath tarchivePath -source_location source_location -timeZone tz

=over 2

=item *
B<-profile prod> : (mandatory) path (absolute or relative to the current directory) of the 
    profile file

=item *
B<-tarchivePath tarchivePath> : (mandatory) absolute path to the DICOM archive

=item *
B<-source_location source_location> : (mandatory) value to set column 
    C<DecompressedLocation> for the newly created record in table C<mri_upload> (see below)
    
=item *
B<-globLocation> : loosen the validity check of the DICOM archive allowing for the 
     possibility that it was moved to a different directory.

=item *
B<-verbose> : be verbose

=back 

=head1 DESCRIPTION

This script first starts by reading the F<prod> file (argument passed to the C<-profile> switch)
to fetch the C<@db> variable, a Perl array containing four elements: the database
name, the database user name used to connect to the database, the password and the 
database hostname. It then checks for an entry in the C<tarchive> table with the same 
C<ArchiveLocation> as the DICOM archive passed on the command line. Let C<T> be the 
DICOM archive record found in the C<tarchive> table. The script will then proceed to scan table 
C<mri_upload> for a record with the same C<tarchiveID> as C<T>'s. If there is none (which is the 
expected outcome), it will insert a record in C<mri_upload> with the following properties/values:

=over 2

=item *
C<UploadedBy> : Unix username of the person currently running F<updateMRI_upload.pl>
   
=item * 
C<uploadDate>: timestamp representing the moment at which F<updateMRI_upload.pl> was run
  
=item *
C<tarchiveID>: value of C<tarchiveID> for record C<T> in table C<tarchive>
  
=item *
C<DecompressedLocation>: argument of the C<-source_location> switch passed on the command line
  
=back

If there already is an entry in C<mri_upload> with the same C<ArchiveLocation> as C<T>'s, the script
will exit with an error message saying that C<mri_upload> is already up to date with respect to
C<T>.

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

Zia Mohades 2014 (zia.mohades@mcgill.ca),
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut

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

use NeuroDB::ExitCodes;

my $verbose = 0;
my $profile    = undef;
my $source_location = '';
my $tarchive = '';
# Default time zone long name. Can be changed with -timeZone
# See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)
my $timeZone = 'local';
my $query = '';
my $sth = undef;
my $User = getpwuid($>);
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

Usage:\n\t $0 -profile <profile> -sourceLocation src -tarchivePath path [-verbose] [-globLocation] [-timeZone tz] 
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
       " tarchive-file"],
      ["-timeZone","string",1, \$timeZone, "Long name for the time zone"]
    );

# Parse arguments
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@arg_table, \@ARGV)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

################################################################
################# checking for profile settings#################
################################################################

if ($timeZone ne 'local' and !DateTime::TimeZone->is_valid_name($timeZone)) {
	print STDERR "Invalid time zone '$timeZone'. "
	    . "See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones"
	    . " for the list of valid time zones.\n";
	exit $NeuroDB::ExitCodes::INVALID_ARG;
}

if ( !$profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

if (-f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
	{ 
        package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" 
    }
}

if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
} 


################################################################
################# if tarchive not specified#####################
################################################################
unless (-e $tarchive) {
    print STDERR "\nERROR: Could not find archive $tarchive.\n"
                 . "Please, make sure the path to the archive is valid.\n\n";
    exit $NeuroDB::ExitCodes::INVALID_PATH;
}

################################################################
#################if the sourcelocation is not set###############
################################################################
unless (-e $source_location) {
    print STDERR "\nERROR: Could not find sourcelocation $source_location\n"
                 . "Please, make sure the sourcelocation is valid.\n\n";
    exit $NeuroDB::ExitCodes::INVALID_PATH;
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

if($resultRef->[0]->{'COUNT(*)'} > 0) {
   print "\n\tERROR: the tarchive is already uploaded \n\n";
   exit $NeuroDB::ExitCodes::FILE_NOT_UNIQUE;
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
my $tarchiveID = $resultRef->[0]->{'TarchiveID'};

################################################################
 #####populate the mri_upload columns with the correct values####
################################################################

$mriUploadOB->insert(
    {
      UploadedBy           => $User,
      UploadDate           => DateTime->now(time_zone => $timeZone)
                                      ->strftime('%Y-%m-%d %H:%M:%S'),
      TarchiveID           => $tarchiveID,
      DecompressedLocation => $source_location
    }
);

print "Done updateMRI_upload.pl execution!\n" if $verbose;
exit $NeuroDB::ExitCodes::SUCCESS;

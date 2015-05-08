#! /usr/bin/perl
use strict;
use warnings;
use Carp;
use Getopt::Tabular;
use FileHandle;
use File::Temp qw/ tempdir /;
use Data::Dumper;
use FindBin;
use Cwd qw/ abs_path /;

################################################################
# These are the NeuroDB modules to be used #####################
################################################################
use lib "$FindBin::Bin";
use NeuroDB::DBI;

my $versionInfo = sprintf "%d revision %2d",
  q$Revision: 1.24 $ =~ /: (\d+)\.(\d+)/;
my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
  localtime(time);
my $date    = sprintf(
                "%4d-%02d-%02d %02d:%02d:%02d",
                $year + 1900,
                $mon + 1, $mday, $hour, $min, $sec
              );
my $debug   = 1;
my $verbose = 1;        # default for now
my $profile = undef;    # this should never be set unless you are in a
                        # stable production environment
my $output              = undef;
my $uploaded_file       = undef;
my $message             = undef;
my @opt_table           = (
    [ "Basic options", "section" ],
    [
        "-profile", "string", 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"
    ],
    [ "Advanced options", "section" ],
    [ "Fancy options", "section" ]
);

my $Help = <<HELP;
******************************************************************************
Imaging_upload_file Cronjob script 
******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo

The program does the following

- Gets a series of rows from mri_uploaded which processed and currentlyprocess
are both set to null
HELP
my $Usage = <<USAGE;
       $0 -help to list options
USAGE
&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV ) || exit 1;

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( $profile && !@Settings::db ) {
    print "\n\tERROR: You don't have a 
    configuration file named '$profile' in:  
    $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit 1;
}

################################################################
################ Establish database connection #################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
my @row=();
my $query = "SELECT UploadID, SourceLocation FROM mri_upload WHERE Processed=0 AND (TarchiveID IS NULL AND number_of_mincInserted IS NULL)";
print "\n" . $query . "\n";
my $sth = $dbh->prepare($query);
$sth->execute();
while(@row = $sth->fetchrow_array()) { 

    if ( -e $row['SourceLocation'] ) {
	my $command = "imaging_upload_file.pl -upload_id $row[0] -profile prod $row[1]";
	print "\n" . $command . "\n";
	my $output = system($command);
    } else {
    	print "\nERROR: Could not find the uploaded file
	       $row[1] for uploadID  $row[0] . \nPlease, make sure "
	      . "the path to the uploaded file exists. 
	      Upload will exit now.\n\n\n";
    }
}
exit 0;

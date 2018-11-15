#! /usr/bin/perl

=pod

=head1 NAME

imaging_upload_file_cronjob.pl -- a wrapper script that calls the single step
script C<imaging_upload_file.pl> for uploaded scans on which the insertion
pipeline has not been launched.

=head1 SYNOPSIS

perl imaging_upload_file_cronjob.pl C<[options]>

Available options are:

-profile      : Name of the config file in C<../dicom-archive/.loris_mri>

-verbose      : If set, be verbose


=head1 DESCRIPTION

The program gets a series of rows from C<mri_upload> on which the insertion
pipeline has not been run yet, and launches it.

=cut

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
use NeuroDB::ExitCodes;

my $versionInfo = sprintf "%d revision %2d",
  q$Revision: 1.24 $ =~ /: (\d+)\.(\d+)/;
my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
  localtime(time);
my $date    = sprintf(
                "%4d-%02d-%02d %02d:%02d:%02d",
                $year + 1900,
                $mon + 1, $mday, $hour, $min, $sec
              );
my $debug   = 0;
my $verbose = 0;        # default for now unless launched with -verbose option
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
    ["-verbose", "boolean", 1,    \$verbose, "Be verbose."]
);

my $Help = <<HELP;
******************************************************************************
Imaging_upload_file Cronjob script 
******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo

The program does the following

- Gets a series of rows from mri_upload which are not currently inserting, nor
have insertion completed

HELP
my $Usage = <<USAGE;
       $0 -help to list options

Documentation: perldoc imaging_upload_file_cronjob.pl

USAGE
&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

if ( !$profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}

################################################################
################ Establish database connection #################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
my @row=();
(my $query = <<QUERY) =~ s/\n/ /gm;
SELECT UploadID, UploadLocation FROM mri_upload 
    WHERE Inserting IS NULL AND InsertionComplete <> 1 
        AND (TarchiveID IS NULL AND number_of_mincInserted IS NULL);
QUERY
print "\n" . $query . "\n" if $debug;
my $sth = $dbh->prepare($query);
$sth->execute();
while(@row = $sth->fetchrow_array()) { 

    if ( -e $row[1] ) {
	my $command =
        "imaging_upload_file.pl -upload_id $row[0] -profile prod $row[1]";
	if ($verbose){
	    $command .= " -verbose";
            print "\n" . $command . "\n";
	}
	my $output = system($command);
    } else {
    	print "\nERROR: Could not find the uploaded file
	       $row[1] for uploadID  $row[0] . \nPlease, make sure "
	      . "the path to the uploaded file exists. 
	      Upload will exit now.\n\n\n";
    }
}
exit $NeuroDB::ExitCodes::SUCCESS;



__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

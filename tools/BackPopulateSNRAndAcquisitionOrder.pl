#! /usr/bin/perl

=pod

=head1 NAME

BackPopulateSNRAndAcquisitionOrder.pl -- a script that back populates the
C<AcqOrderPerModality> column of the C<files> table, and the signal-to-noise
ratio (SNR) values in the C<parameter_file> table for inserted MINC files. The
SNR is computed using MINC tools built-in algorithms.


=head1 SYNOPSIS

perl tools/BackPopulateSNRAndAcquisitionOrder.pl C<[options]>

Available options are:

-profile    : name of the config file in C<../dicom-archive/.loris_mri>

-tarchive_id: ID of the DICOM archive (.tar file) to be processed from the
               C<tarchive> table



=head1 DESCRIPTION

This script will back populate the C<files> table with entries for the
C<AcqOrderPerModality> column; in reference to:
https://github.com/aces/Loris-MRI/pull/160
as well as populate the C<parameter_file> table with SNR entries in reference
to: https://github.com/aces/Loris-MRI/pull/142
It can take in C<TarchiveID> as an argument if only a specific DICOM archive
(.tar files) is to be processed; otherwise, all DICOM archives (C<tar>
files) in the C<tarchive> table are processed.


=cut


use strict;
use warnings;
use Getopt::Tabular;
use File::Temp qw/ tempdir /;
use File::Basename;
use File::Find;
use Cwd;
use NeuroDB::DBI;
use NeuroDB::MRIProcessingUtility;
use NeuroDB::ExitCodes;

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
      "tarchive_id of the DICOM archive (.tar files) to be processed from tarchive table"
    ]
); 

my $Help = <<HELP;

This script will back populate the files table with entries for the
AcqOrderPerModality column; in reference to:
https://github.com/aces/Loris-MRI/pull/160
as well as populate the parameter_file table with SNR entries in reference to:
https://github.com/aces/Loris-MRI/pull/142
It can take in TarchiveID as an argument if only a specific DICOM archive
(.tar files) is to be processed; otherwise, all DICOM archives (.tar files) in
the tarchive table are processed.


Documentation: perldoc BackPopulateSNRAndAcquisitionOrder.pl

HELP

my $Usage = <<USAGE;

Usage: $0 -help to list options

USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

################################################################
################### input option error checking ################
################################################################
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
    $query = "SELECT TarchiveID, ArchiveLocation, SourceLocation " .
        "FROM tarchive";
}
# Selecting tarchiveID is redundant here but it makes the while() loop
# applicable to both cases; when a TarchiveID is specified or not
else {
    $query = "SELECT TarchiveID, ArchiveLocation, SourceLocation " .
        "FROM tarchive ".
        "WHERE TarchiveID = $TarchiveID ";
}

my $sth = $dbh->prepare($query);
$sth->execute();
    
if($sth->rows > 0) {
	# Create tarchive list hash with old and new location
    while ( my $rowhr = $sth->fetchrow_hashref()) {    
        $TarchiveID        = $rowhr->{'TarchiveID'};
        my $ArchLoc        = $rowhr->{'ArchiveLocation'};
        my $SourceLocation = $rowhr->{'SourceLocation'};
        # grep the upload_id from the tarchive's source location
        my $upload_id = NeuroDB::MRIProcessingUtility::getUploadIDUsingTarchiveSrcLoc(
            $SourceLocation
        );
		print "Currently updating the SNR for applicable files in parameter_file table ".
            "for tarchiveID $TarchiveID at location $ArchLoc\n";    
        $utility->computeSNR($TarchiveID, $upload_id);
		print "Currently updating the Acquisition Order per modality in files table\n";    
        $utility->orderModalitiesByAcq($TarchiveID, $upload_id);

		print "Finished updating back-populating SNR and Acquisition Order ".
            "per modality for TarchiveID $TarchiveID \n";
	}
}
else {
	print "No tarchives to be updated \n";	
}

$dbh->disconnect();
exit $NeuroDB::ExitCodes::SUCCESS;


__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

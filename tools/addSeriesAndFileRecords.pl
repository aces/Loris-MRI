#!/usr/bin/perl 
# Jonathan Harlap
# jharlap@bic.mni.mcgill.ca
# Perl tool based on DCMSUM.pm and DICOM.pm to populate the series and file tables for a tarchive
# @VERSION : $Id: addSeriesAndFileRecords.pl 4 2007-12-11 20:21:51Z jharlap $

use strict;
use Cwd qw/ abs_path /;
use Getopt::Tabular;
use FileHandle;
use File::Temp qw/ tempdir /;
use File::Basename;

use DICOM::DICOM;
use DICOM::DCMSUM;
use NeuroDB::DBI;

my $profile;
my $verbose  = 0;
my $version  = 0;
my $versionInfo = sprintf "%d", q$Revision: 4 $ =~ /: (\d+)/;

################################
# array of dicom dirs
my @dcmDirs;

my $Usage = "------------------------------------------

  Author    :        Jonathan Harlap
  Date      :        2007/03/27
  Version   :        $versionInfo


WHAT THIS IS:

A tool to repopulate the tarchive_series and tarchive_files tables for an existing tarchive.

Usage:\n\t $0 </PATH/TO/TARCHIVE.tar> [options]
\n\n See $0 -help for more info\n\n";

my @arg_table =
    (
     ["Main options","section"],
     ["-profile","string",1, \$profile, "Specify the name of the config file which resides in .loris_mri in the current directory."],

     ["General options", "section"],
     ["-verbose","boolean",1,  \$verbose, "Be verbose."],
     ["-version","boolean",1,  \$version, "Print version and revision number and exit"],
     );

GetOptions(\@arg_table, \@ARGV) || exit 1;

# print version info and quit
if ($version) { print "$versionInfo\n"; exit; }

# checking for profile settings
if($profile && -f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") { { package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" } }    
if ($profile && !@Settings::db) { print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; exit 33; }


# basic error checking on tarchive
if(scalar(@ARGV) != 1) { print $Usage; exit 1; }
my $tarchive = abs_path($ARGV[0]);

# establish database connection if database option is set
my $dbh;
$dbh = &NeuroDB::DBI::connect_to_db(@Settings::db); print "Testing for database connectivity. \n" if $verbose; $dbh->disconnect(); print "Database is available.\n\n" if $verbose;

####################### main ########################################### main ########################################### 

my ($studyUnique, $metaname, @metaFiles, $dcmdir, $sumTypeVersion);

# make temp dir
my $TmpDir = tempdir( CLEANUP => 1 );

# extract the tarchive
my $dcmdir = &extract_tarchive($tarchive, $TmpDir);

# create new summary object
my $summary = DICOM::DCMSUM->new($TmpDir.'/'.$dcmdir,$TmpDir);

# determine the name for the summary file
$metaname = $summary->{'metaname'};

# get the summary type version
$sumTypeVersion = $summary->{'sumTypeVersion'};

# get the unique study ID
$studyUnique = $summary->{'studyuid'};


# if -dbase has been given create an entry based on unique studyID
# Create database entry checking for already existing entries...
$dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# now get the TarchiveID
my $tarchiveID;
my $tarchiveBasename = basename($tarchive);
(my $query = <<QUERY) =~ s/\n/ /gm;
SELECT 
  TarchiveID 
FROM 
  tarchive 
WHERE 
  DicomArchiveID=?
  AND ArchiveLocation like ?
QUERY
my $sth   = $dbh->prepare($query);
$sth->execute($summary->{studyuid}, "%${tarchiveBasename}");
my @row = $sth->fetchrow_array();
$tarchiveID = $row[0];

if($tarchiveID > 0) {
    print "Determined TarchiveID = $tarchiveID\n";
} else {
    print "Could not determine TarchiveID for tarchive $tarchive\n";
    exit 1;
}

# nuke series and files records then reinsert them
(my $delete_series = <<QUERY) =~ s/\n/ /gm;
DELETE FROM
  tarchive_series
WHERE
  TarchiveID=?
QUERY
(my $delete_files = <<QUERY) =~ s/\n/ /gm;
DELETE FROM
  tarchive_files
WHERE
  TarchiveID=?
QUERY
$sth = $dbh->prepare($delete_series);
$dbh->execute($tarchiveID);
$sth = $dbh->prepare($delete_files);
$dbh->execute($tarchiveID);

# now create the tarchive_series records
($query = <<QUERY) =~ s/\n/ /gm;
INSERT INTO 
  tarchive_series 
    (
     TarchiveID,    SeriesNumber,   SeriesDescription, SequenceName, 
     EchoTime,      RepetitionTime, InversionTime,     SliceThickness, 
     PhaseEncoding, NumberOfFiles,  SeriesUID
    ) 
  VALUES
    (
     ?,             ?,              ?,                 ?, 
     ?,             ?,              ?,                 ?, 
     ?,             ?,              ?
    )
QUERY
my $insert_series = $dbh->prepare($query);
foreach my $acq (@{$summary->{acqu_List}}) {
    # insert the series
    my ($seriesNum, $sequName,  $echoT, $repT, $invT, $seriesName, $sl_thickness, $phaseEncode, $seriesUID, $num) = split(':::',$acq);
    my @values = 
      (
       $tarchiveID,  $seriesNum, $seriesName, $sequName,  
       $echoT,       $repT,      $invT,       $sl_thickness, 
       $phaseEncode, $num,       $seriesUID
      );
    $insert_series->execute(@values);
}

# now create the tarchive_files records
($query = <<QUERY) =~ s/\n/ /gm;
INSERT INTO 
  tarchive_files 
    (
     TarchiveID,        SeriesNumber, FileNumber, EchoNumber, 
     SeriesDescription, Md5Sum,       FileName
    ) 
  VALUES 
    (
     ?,                 ?,            ?,          ?, 
     ?,                 ?,            ?
    )
QUERY
my $insert_file = $dbh->prepare($query);
foreach my $file (@{$summary->{'dcminfo'}}) {
    # insert the file
    my $filename = $file->[4];
    $filename =~ s/^${TmpDir}\///;
    my @values;
    if($file->[21]) { # file is dicom
        @values = 
          (
           $tarchiveID, $file->[1],  $file->[3], $file->[2], 
           $file->[12], $file->[20], $filename
          );
        $insert_file->execute(@values);
    } else {
        @values =
          (
           $tarchiveID, undef,       undef,     undef, 
           undef,       $file->[20], $filename 
          );
        $insert_file->execute(@values);
    }
}

print "Done!\n";

exit;


######################################################################### end main ####################
=pod 
################################################
Extract a tarchive into a temp dir
################################################
=cut 
sub extract_tarchive {
	 my ($tarchive, $tempdir) = @_;

	 print "Extracting tarchive\n" if $verbose;
	 `cd $tempdir ; tar -xf $tarchive`;
	 opendir TMPDIR, $tempdir;
	 my @tars = grep { /\.tar\.gz$/ && -f "$tempdir/$_" } readdir(TMPDIR);
	 closedir TMPDIR;

	 if(scalar(@tars) != 1) {
		  print "Error: Could not find inner tar in $tarchive!\n";

		  print @tars . "\n";
		  exit(1);
	 }

	 my $dcmtar = $tars[0];
	 my $dcmdir = $dcmtar;
	 $dcmdir =~ s/\.tar\.gz$//;

	 `cd $tempdir ; tar -xzf $dcmtar`;
	 
	 return $dcmdir;
}


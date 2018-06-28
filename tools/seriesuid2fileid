#!/usr/bin/perl

=pod

=head1 NAME

seriesuid2fileid -- a script that displays a report about the pipeline insertion
progress and outcome (including MRI violation status) of imaging datasets, based
on series C<UID(s)> provided as C<STDIN>.

=head1 SYNOPSIS

perl tools/seriesuid2fileid

There are no available options. Once the script is invoked, series C<UID> can be
input to display the status. The C<$profile> file for database connection
credentials is assumed to be C<prod>.


=head1 DESCRIPTION

The program takes series C<UID> from C<STDIN> and returns a report with:

  - C<SeriesUID>
  - C<SeriesDescription>
  - C<TarchiveID>
  - C<m_p_v_s_ID>
  - C<mri_v_log>
  - C<FileID>
  - C<FileName>

The C<m_p_v_s_ID> column displays, if present, the C<ID> record from the
C<mri_protocol_violated_scans> table together with a count representing the
number of times this scan violated the study MRI protocol, and the C<mri_v_log>
displays the C<Severity> level of the violations as defined in the
C<mri_protocol_checks> table.

=cut

use strict;
use warnings;
no warnings 'once';
use Data::Dumper;
use File::Basename;
use Term::ANSIColor qw(:constants);
use NeuroDB::DBI;

my $Help = <<HELP;
*******************************************************************************
SeriesUID 2 fileID
*******************************************************************************

Author  :   Gregory Luneau
Date    :   October 2016
Version :   1


The program does the following:

Takes SeriesUID from STDIN and returns a report with:

- SeriesUID
- SeriesDescription
- TarchiveID
- m_p_v_s_ID
- mri_v_log
- FileID
- FileName

Documentation: perldoc seriesuid2fileid

HELP

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/prod" }
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

my $queryF = "SELECT * FROM files as f WHERE f.SeriesUID=?";
my $queryT = "SELECT * FROM tarchive_series as t LEFT JOIN tarchive as a USING (TarchiveID) WHERE t.SeriesUID=?";
my $queryM = "SELECT * FROM mri_protocol_violated_scans as m WHERE m.SeriesUID=? OR (m.PatientName=? AND m.series_description=?)";
my $queryV = "SELECT * FROM mri_violations_log as v WHERE v.SeriesUID=?";
my $queryP = "SELECT (SELECT pf.`VALUE` FROM parameter_file AS pf WHERE pf.FileID=? AND pf.ParameterTypeID=(SELECT p.ParameterTypeID FROM parameter_type as p WHERE p.Name='xspace')) AS xspace, (SELECT pf.`VALUE` FROM parameter_file AS pf WHERE pf.FileID=? AND pf.ParameterTypeID=(SELECT p.ParameterTypeID FROM parameter_type as p WHERE p.Name='zspace')) AS zspace, IFNULL((SELECT pf.`VALUE` FROM parameter_file AS pf WHERE pf.FileID=? AND pf.ParameterTypeID=(SELECT p.ParameterTypeID FROM parameter_type as p WHERE p.Name='time')), 1) as time";

my $sthF = $dbh->prepare($queryF);
my $sthT = $dbh->prepare($queryT);
my $sthM = $dbh->prepare($queryM);
my $sthV = $dbh->prepare($queryV);
my $sthP = $dbh->prepare($queryP);

my ($rF, $rT, $rM, $rV, $rP);
my ($fF, $fT, $fM, $fV, $fP);

my ($SeriesDescription, $TarchiveID, $FileID, $ID, $Severity, $PatientName, $NumberOfFiles, $ZxT, $FileName);

printf ("%-6s", '| L# ');
printf ("%-64s",'| SeriesUID');
printf ("%-36s",'| SeriesDescription');
printf ("%-16s",'| TarchiveID');
printf ("%-13s",'| m_p_v_s_ID');
printf ("%-12s",'| mri_v_log');
printf ("%-16s",'| FileID');
printf ("%-36s",'| FileName');

print "|\n";

while (<STDIN>) {

  chomp($_);

  $rF = $sthF->execute($_);
  $fF = $sthF->fetchrow_hashref();

  $rT = $sthT->execute($_);
  $fT = $sthT->fetchrow_hashref();

  $rV = $sthV->execute($_);
  $fV = $sthV->fetchrow_hashref();

  #print Dumper($f);

  if ($sthT->rows > 0) {
    $SeriesDescription = $fT->{'SeriesDescription'};
    $TarchiveID        = $fT->{'TarchiveID'};
    $PatientName       = $fT->{'PatientName'};
    $NumberOfFiles     = ' (' . $fT->{'NumberOfFiles'} . ')';
  } else {
    $SeriesDescription = '';
    $TarchiveID        = '';
    $NumberOfFiles     = '';
  }

  $rM = $sthM->execute($_, $PatientName, $SeriesDescription);
  $fM = $sthM->fetchrow_hashref();

  if ($sthM->rows > 0) {
    $ID = $fM->{'ID'} . " (" . $sthM->rows . ")";
  } else {
    $ID = '';
  }

  if ($sthF->rows > 0) {
    $FileID = $fF->{'FileID'};
    $FileName = basename($fF->{'File'});
    $rP = $sthP->execute($FileID, $FileID, $FileID);
    $fP = $sthP->fetchrow_hashref();

    if ($sthP->rows > 0) {
      $ZxT = ' (' . $fP->{'zspace'} * $fP->{'time'} . ')';
      # $ZxT = ' (' . $fP->{'xspace'} * $fP->{'time'} . ')';
    } else {
      $ZxT = '';
    }
  } elsif (index($SeriesDescription, "localizer") != -1) {
    $FileID = 'exclude';
    $ZxT = '';
    $FileName = '';
  } else {
    $FileID = '';
    $ZxT = '';
    $FileName = '';
  }

  if ($sthV->rows > 0) {
    $Severity = $fV->{'Severity'};
  } else {
    $Severity = '';
  }

#  print "$.,$_,$SeriesDescription,$TarchiveID,$FileID\n";

  printf ("%-6s", '| '. $.);
  printf ("%-64s",'| '. $_);
  printf ("%-36s",'| '. $SeriesDescription);
  printf ("%-16s",'| '. $TarchiveID . $NumberOfFiles);
  printf ("%-13s",'| '. $ID);
  printf ("%-12s",'| '. $Severity);
  printf ("%-16s",'| '. $FileID . $ZxT);
  printf ("%-36s",'| '. $FileName);
  print  "|\n";
 
}


__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

Gregory Luneau,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut

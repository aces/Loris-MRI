#!/usr/bin/perl
use strict;
use warnings;
no warnings 'once';
use Data::Dumper;
use File::Basename;
use File::Copy;
use Term::ANSIColor qw(:constants);
use NeuroDB::DBI;

my $profile = "prod";
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/" . $profile}
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);


if (!empty($argv[1]) {
  if ($argv[1] eq "insertminc") {
    my $insertminc = 1;
  }
}

# Only the f.SeriesUID is really needed for minc_deletion, other fields are for information only
my $queryF = <<SQL;
    SELECT DISTINCT
    f.FileID, f.File, f.SeriesUID, t.ArchiveLocation, SUBSTRING_INDEX(t.ArchiveLocation, '/', -1) as tarchive
    FROM files AS f
    LEFT JOIN session s ON (f.SessionID=s.ID)
    LEFT JOIN parameter_file AS pf USING (FileID)
    LEFT JOIN files_qcstatus AS fq USING (FileID)
    LEFT JOIN tarchive AS t ON f.TarchiveSource=t.TarchiveID
    WHERE f.SeriesUID='1.3.12.2.1107.5.2.32.35177.2015072521545163128256406.0.0.0' or f.SeriesUID='1.3.12.2.1107.5.2.32.35177.2015072822492087585653675.0.0.0' and
    ((pf.ParameterTypeID=329 and pf.`VALUE` like '%acquisition:direction_x = 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=329 and pf.`VALUE` like '%acquisition:direction_y = 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=329 and pf.`VALUE` like '%acquisition:direction_z = 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=333 and pf.`VALUE` like '%0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=334 and pf.`VALUE` like '%0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=343 and pf.`VALUE` like '%0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%'))
    ORDER BY f.FileID
SQL

my $sthF = $dbh->prepare($queryF);

my $keepgoing = 1;
my ($rF, $fF, $stdin, $i);

printf ("%-6s", '| L# ');
printf ("%-64s",'| SeriesUID');
printf ("%-20s",'| Value');
printf ("%-20s",'| Scan Type');
printf ("%-60s",'| File');
print "|\n";

$rF = $sthF->execute();

while ($fF = $sthF->fetchrow_hashref()) {

  if ($sthF->rows > 0) {
    $i++;

    printf ("%-6s", '| '. $i);
    printf ("%-64s",'| '. $fF->{'SeriesUID'});
    printf ("%-20s",'| '. $fF->{'Value'});
    printf ("%-20s",'| '. $fF->{'Scan_type'});
    printf ("%-60s",'| '. $fF->{'file'});
    print  "|\n";

    if ($keepgoing) {
      print "Press ENTER (or A and ENTER to do it all)\n";
      $stdin = <STDIN>;
      if ($stdin eq "A\n") {
        print "Ok, I will keep going until it's done.\n";
        $keepgoing = 0;
      }
    }

    my $minc_delete_cmd = "../uploadNeuroDB/minc_deletion.pl -profile " . $profile . " -seriesuid " . $fF->{'SeriesUID'} . " confirm";
    print $minc_delete_cmd . "\n";
    my $minc_delete_log = `$minc_delete_cmd`;
    print $minc_delete_log . "\n";

    if ($insertminc) {
      my $tar_loader_cmd  = "../uploadNeuroDB/tarchiveLoader -profile " . $profile . " -seriesuid " . $fF->{'SeriesUID'} . " -verbose -globLocation " . $fF->{'ArchiveLocation'};
      print $tar_loader_cmd . "\n";
      my $tar_loader_log  = `$tar_loader_cmd`;
      print $tar_loader_log . "\n";
    }
  }
}

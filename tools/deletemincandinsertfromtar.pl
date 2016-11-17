#!/usr/bin/perl
use strict;
use warnings;
no warnings 'once';
use Data::Dumper;
use File::Basename;
use File::Copy;
use Term::ANSIColor qw(:constants);
use NeuroDB::DBI;

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/prod" }
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# my $queryF = "SELECT f.SeriesUID, a.ArchiveLocation, SUBSTRING_INDEX(a.ArchiveLocation, '/', -1) as tarchive, ".
#             "CASE WHEN t.SeriesDescription LIKE '%t1%' THEN 't1w' WHEN t.SeriesDescription LIKE '%t2%' THEN 't2w' END AS protocol FROM files AS f ".
#             "LEFT JOIN tarchive_series AS t ON t.SeriesUID=f.SeriesUID LEFT JOIN tarchive AS a ON f.TarchiveSource=a.TarchiveID ".
#             "where f.file LIKE '%dti%' AND (t.SeriesDescription LIKE '%t1%' OR t.SeriesDescription LIKE '%t2%') ".
#             "AND f.SeriesUID NOT IN ('1.3.12.2.1107.5.2.32.35182.2008073113303686337017814.0.0.0','1.3.12.2.1107.5.2.43.67010.2015042819301841366299600.0.0.0') ".
#             "ORDER BY f.FileID, t.SeriesDescription";

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
printf ("%-36s",'| ArchiveLocation');
printf ("%-36s",'| CorrectLocation');

print "|\n";

$rF = $sthF->execute();

while ($fF = $sthF->fetchrow_hashref()) {

  if ($sthF->rows > 0) {
    $i++;

    # copy("/data/not_backed_up/ibis_t1t2/backup/" . $fF->{'tarchive'}, "/data/not_backed_up/ibis_t1t2/");

    my $minc_delete_cmd = "../uploadNeuroDB/minc_deletion.pl -profile prod -seriesuid " . $fF->{'SeriesUID'} . " confirm";
    print $minc_delete_cmd . "\n";
    my $minc_delete_log = `$minc_delete_cmd`;
    print $minc_delete_log . "\n";

    print "Press ENTER to continue:";
    <STDIN>;

    # -acquisition_protocol " . $fF->{'protocol'}
    # -profile prod
    # ../../../../" . $fF->{'ArchiveLocation'}
    my $tar_loader_cmd  = "../uploadNeuroDB/tarchiveLoader -profile null_grads -seriesuid " . $fF->{'SeriesUID'} .
                          " -verbose -globLocation " . $fF->{'ArchiveLocation'};

    print $tar_loader_cmd . "\n";
    my $tar_loader_log  = `$tar_loader_cmd`;
    print $tar_loader_log . "\n";

    printf ("%-6s", '| '. $i);
    printf ("%-64s",'| '. $fF->{'seriesuid'});
    printf ("%-36s",'| '. $fF->{'ArchiveLocation'});
    printf ("%-36s",'| '. $fF->{'tarchive'});
    print  "|\n";

    if ($keepgoing) {
      print "Press ENTER (or A and ENTER to do it all)\n";
      $stdin = <STDIN>;
      if ($stdin eq "A\n") {
        print "Ok, I will keep going until it's done.\n";
        $keepgoing = 0;
      }
    }
  }
}

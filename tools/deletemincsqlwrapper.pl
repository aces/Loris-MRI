#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Tabular;
no warnings 'once';
use Data::Dumper;
use File::Basename;
use File::Copy;
use Term::ANSIColor qw(:constants);
use NeuroDB::DBI;

my $profile = "prod";
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/" . $profile}
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# Only the f.SeriesUID is really needed for minc_deletion, other fields are for information only
my $queryF = <<SQL;
  select f.fileid, f.SeriesUID, f.SessionID, f.file, from_unixtime(f.InsertTime), p.Value, q.QCStatus, c.Alias, m.Scan_type
  from files as f 
  left join parameter_file as p using (FileID)
  left join parameter_type as t using (ParameterTypeID)
  left join files_qcstatus as q using (FileID)
  left join session as s on (f.SessionID=s.ID)
  left join psc as c on (c.CenterID=s.CenterID)
  left join mri_scan_type as m on (m.ID=f.AcquisitionProtocolID)
  and p.Value like '%4.%'
  and (m.Scan_type like '%t1%' or m.Scan_type like '%t2%')
  order by f.InsertTime
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

    my $minc_delete_cmd = "uploadNeuroDB/minc_deletion.pl -profile " . $profile . " -seriesuid " . $fF->{'SeriesUID'} . " confirm";
    print $minc_delete_cmd . "\n";
    my $minc_delete_log = `$minc_delete_cmd`;
    print $minc_delete_log . "\n";

    if ($insertminc) {
      my $tar_loader_cmd  = "uploadNeuroDB/tarchiveLoader -profile " . $profile . " -seriesuid " . $fF->{'SeriesUID'} . " -verbose -globLocation " . $fF->{'ArchiveLocation'};
      print $tar_loader_cmd . "\n";
      my $tar_loader_log  = `$tar_loader_cmd`;
      print $tar_loader_log . "\n";
    }
  }
}

#!/usr/bin/perl

=pod

=head1 NAME

deletemincsqlqrapper.pl -- This script is a wrapper for deleting multiple MINC
files at a time and optionally re-inserting them. It will pause for confirmation
before deleting. B<Projects should modify the query as needed to suit their
needs>.

=head1 SYNOPSIS

perl tools/example_scripts/deletemincsqlqrapper.pl C<[options]>

Available options are:

-profile      : Name of the config file in
                C<../../dicom-archive/.loris_mri>

-insertminc   : Re-insert the deleted MINC



=head1 DESCRIPTION

This is an B<example> script that does the following:
 - Deletes multiple MINC files fitting a common criterion from the database.
 - Provides the option to re-insert deleted scans with their series UID when
   using the C<-insertminc> flag.

B<Notes:>
 - B<Projects should modify the query as they see fit to suit their needs>.
 - For the example query provided (in C<$queryF>), all inserted scans with types
   like C<t1> or C<t2>, having a C<slice thickness> in the range of C<4 mm> will
   be deleted.
    - A use-case of this deletion query might be that initially the project did
    not exclude C<t1> or C<t2> modalities having 4 mm slice thickness, and
    subsequently, the study C<mri_protocol> table has been changed to add
    tighter checks on slice thickness.


=cut

use strict;
use warnings;
use Getopt::Tabular;
no warnings 'once';
use Data::Dumper;
use File::Basename;
use File::Copy;
use Term::ANSIColor qw(:constants);
use NeuroDB::DBI;
use NeuroDB::ExitCodes;

my $profile = undef;
my $insertminc;

my @opt_table           = (
    [ "Basic options", "section" ],
    [
        "-profile", "string", 1, \$profile,
        "name of config file in ../../dicom-archive/.loris_mri"
    ],
    [   
         "-insertminc", "boolean", 0, \$insertminc, "Re-insert the deleted MINC"
    ]
);

my $Help = <<HELP;
*******************************************************************************
Wrapper to minc_deletion.pl for bulk deletion based on a SQL customisable query
*******************************************************************************

This script is a wrapper for deleting multiple MINC files at a time and
optionally re-inserting them. It will pause for confirmation before deleting.

Please note that this is an example script. Projects need to customize the query
based on their needs. Please refer to the associated documentation file in the
docs/scripts_md/ directory for more details. Alternatively, the documentation on
this script can be obtained as follows:


Documentation: perldoc tools/example_scripts/deletemincsqlwrapper.pl

HELP

my $Usage = <<USAGE;
usage: tools/example_scripts/deletemincsqlwrapper.pl -profile prod
       $0 -help to list options
USAGE
&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/" . $profile}
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);



# Only the f.SeriesUID is really needed for minc_deletion, other fields are for information only
# If you plan to re-insert, you'll also need ArchiveLocation
my $queryF = <<SQL;
  SELECT DISTINCT f.fileid, f.SeriesUID, f.SessionID, f.file, t.ArchiveLocation, FROM_UNIXTIME(f.InsertTime), p.Value, q.QCStatus, c.Alias, m.Scan_type
  FROM files AS f
  LEFT JOIN parameter_file AS p using (FileID)
  LEFT JOIN parameter_type AS pt using (ParameterTypeID)
  LEFT JOIN files_qcstatus AS q using (FileID)
  LEFT JOIN session AS s ON (f.SessionID=s.ID)
  LEFT JOIN psc AS c ON (c.CenterID=s.CenterID)
  LEFT JOIN mri_scan_type AS m ON (m.ID=f.AcquisitionProtocolID)
  LEFT JOIN tarchive AS t ON f.TarchiveSource=t.TarchiveID
  WHERE pt.Name = 'acquisition:slice_thickness'
  AND p.Value LIKE '%4.%'
  AND (m.Scan_type LIKE '%t1%' OR m.Scan_type LIKE '%t2%')
  ORDER BY FROM_UNIXTIME(f.InsertTime)
SQL


my $sthF = $dbh->prepare($queryF);

my $keepgoing = 1;
my ($fF, $stdin, $i);

printf ("%-6s", '| L# ');
printf ("%-64s",'| SeriesUID');
printf ("%-20s",'| Value');
printf ("%-20s",'| Scan Type');
printf ("%-60s",'| File');
print "|\n";

$sthF->execute();

if ($sthF->rows > 0) {

  while ($fF = $sthF->fetchrow_hashref()) {

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
      # Running tarchiveLoader on the archived tar as a whole will only insert new minc files that are not already in the files table 
      my $tar_loader_cmd  = "uploadNeuroDB/tarchiveLoader -profile " . $profile . " -verbose -globLocation " . $fF->{'ArchiveLocation'};
      print $tar_loader_cmd . "\n";
      my $tar_loader_log  = `$tar_loader_cmd`;
      print $tar_loader_log . "\n";
    }
  }
} else {
    print "\n***No files were found that match the following query:***\n\n" . $queryF . "\n";
}



__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

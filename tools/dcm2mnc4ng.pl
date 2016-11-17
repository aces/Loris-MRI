#!/usr/bin/perl
use strict;
use warnings;
no warnings 'once';
use Data::Dumper;
use File::Basename;
use Term::ANSIColor qw(:constants);
use NeuroDB::DBI;

my $Help = <<HELP;
*******************************************************************************
Dicom to Minc for Null Grads
*******************************************************************************

Author  :   Gregory Luneau
Date    :   November 2016
Version :   1


The program does the following:



There are no arguments so far.

HELP

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/prod" }
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

my $queryF = <<SQL;
    SELECT DISTINCT
    f.FileID, f.File, f.SeriesUID, t.ArchiveLocation
    FROM files as f
    left JOIN session s ON (f.SessionID=s.ID)
    left join parameter_file as pf using (FileID)
    LEFT JOIN files_qcstatus as fq USING (FileID)
    left join tarchive as t on f.TarchiveSource=t.TarchiveID
    WHERE ((pf.ParameterTypeID=329 and pf.`VALUE` like '%acquisition:direction_x = 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=329 and pf.`VALUE` like '%acquisition:direction_y = 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=329 and pf.`VALUE` like '%acquisition:direction_z = 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=333 and pf.`VALUE` like '%0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=334 and pf.`VALUE` like '%0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%')
     or (pf.ParameterTypeID=343 and pf.`VALUE` like '%0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0., 0.%'))
    order by f.FileID

SQL

my $sthF = $dbh->prepare($queryF);

my ($rF, $fF, $SeriesUID);


printf ("%-36s",'| SeriesDescription');


print "|\n";

$rF = $sthF->execute();

while ($fF = $sthF->fetchrow_hashref()) {

    $SeriesUID = $fF->{'SeriesDescription'};

    printf ("%-36s",'| '. $SeriesUID);

    print  "|\n";
 
}

#! /usr/bin/perl
use strict;
use warnings;
use Carp;
use Getopt::Tabular;
use FileHandle;
use File::Basename;
use File::Temp qw/ tempdir /;
use File::Path qw/ make_path /;
use Data::Dumper;
use FindBin;
use Cwd qw/ abs_path /;

# These are the NeuroDB modules to be used
use lib "$FindBin::Bin";
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::Notify;
use NeuroDB::MRIProcessingUtility;

my $sessionfilesfound = '';
my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.3 $
    =~ /: (\d+)\.(\d+)/;
my $profile   = '';      # this should never be set unless you are in a
                             # stable production environment
my $seriesuid = '';
my $fileid    = '';
my $sth;
my $rvl;
my $query     = '';
my $selORdel  = '';
my $delqcdata = '';
my $sUIDFiles = 0;
my @opt_table = (
                 ["Basic options","section"],
                 ["-profile     ","string",1, \$profile,
                  "config file in ../dicom-archive/.loris_mri"
                 ],
                 ["-seriesuid", "string", 1, \$seriesuid, "Only deletes this SeriesUID"
                 ],
                 ["-fileid", "string", 1, \$fileid, "Only deletes this FileID"
                 ],
                 ["-delqcdata", "boolean", 1, \$delqcdata, "Deletes QC data"
                 ],
                 );

my $val;
my $field;
my $Help = <<HELP;
*******************************************************************************
Minc Deletion
*******************************************************************************

Author  :   Gregory Luneau
Date    :   July 2016
Version :   $versionInfo


The program does the following:

Deletes minc files from Loris by:
  - Moving the existing files to an archive directory.
    .mnc .nii .jpg .header .raw_byte.gz
  - Deleting all related data from 2 database tables.
    parameter_file & files
  - Deletes data from files_qcstatus & feedback_mri_comments
    database tables if the -delqcdata is set. In most cases
    you would want to delete this when the images changes.
  - Deletes mri_acquisition_dates entry if it is the last file
    removed from that session.

Use the argument "select" to view the record that could be removed
from the database.  Use "confirm" to acknowledge that the data in 
the database will be deleted once the script executes.

HELP
my $Usage = <<USAGE;
usage: $0 [options] select|confirm
       $0 -help to list options

USAGE
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;

################################################################
################### input option error checking ################
################################################################
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ($profile && !@Settings::db) { 
    print "\n\tERROR: You don't have a configuration file named ". 
          "'$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit 2; 
}
if (!$ARGV[0] || !$profile) { 
    print $Help;
    print " ERROR: You must type select or confirm and have an ".
          "existing profile.\n\n";
    exit 3;  
}
if (!$seriesuid && !$fileid) {
    print " ERROR: You must specify either a seriesuid or a fileid ".
          "option.\n\n";
    exit 4;
}
if ($seriesuid && $fileid) {
    print " ERROR: You cannot specify both a seriesuid and a fileid ".
          "option.\n\n";
    exit 5;
}



if ($ARGV[0] eq "confirm") {
  $selORdel  = "DELETE ";
} else {
  $selORdel  = "SELECT * ";
}

my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
my $data_dir = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'dataDirBasepath'
                    );

sub selORdel {
  my ($table, $field) = @_;
  my $where = '';
  my $fileidq = "SELECT FileID FROM files WHERE SeriesUID = ?";

  if ($seriesuid) {
    if ($table eq "parameter_file") {
      $where = " WHERE FileID = ?";
    } else {
      $where = " WHERE SeriesUID = ?";
    }
  } elsif ($fileid) {
    $where = " WHERE FileID = ?";
  }

  my $query = $selORdel . "FROM " . $table . $where;

  my $sth = $dbh->prepare($query);
  my $stq = $dbh->prepare($fileidq);

  if ($seriesuid) {
    if ($table eq "parameter_file") {
      $stq->execute($seriesuid);
      # Taking care of multiple seriesuid
      while (my $st = $stq->fetchrow_hashref()) {
        $fileid .= $st->{'FileID'} . ",";
        $sth->execute($st->{'FileID'});
      }
      chop($fileid);
    } else {
      $sth->execute($seriesuid)
    }
  } elsif ($fileid) {
    $sth->execute($fileid);
  }

  if ($selORdel eq "SELECT * ") {
    if ($seriesuid) {
      if ($table eq "parameter_file") {
       $query =~ s/= \?/IN ($fileid)/g;
       undef $fileid;
      } else { 
       $query =~ s/\?/'$seriesuid'/g;
      }
    } elsif ($fileid) {
      $query =~ s/\?/'$fileid'/g;
    }
    print "\n" . $query;
  }
}


# Delete from FS:
# get the file names
$query = "select f.File, f.TarchiveSource, f.SessionID, pf.`VALUE` from files as f ".
         "left join parameter_file as pf using (FileID) where ".
         "pf.ParameterTypeID = (select pt.ParameterTypeID from parameter_type as pt where pt.Name = 'check_pic_filename') and ".
         "pf.FileID IN ";

# Useful database tracing for troubleshooting
# $dbh->trace(5);

if ($seriesuid) {
  $query .= "(SELECT FileID FROM files WHERE SeriesUID = ?)";
  $sth = $dbh->prepare($query);
  $rvl = $sth->execute($seriesuid);
} elsif ($fileid) {
  $query .= "(?)";
  $sth = $dbh->prepare($query);
  $rvl = $sth->execute($fileid);
}

if ($sth->err) {
  die "ERROR! return code:" . $sth->err . " error msg: " . $sth->errstr . "\n";
}

if (defined $rvl && $rvl == 0) {
  die "Can't rename if there is no value return from: \n" . $query . "\n";
}


my ($tarchiveid, $sessionid, @pic_path, $jiv_header, $jiv_raw_byte, $file, $dir, $ext, $nii_file, @candid);

while (my $f = $sth->fetchrow_hashref()) {
  $tarchiveid   = $f->{'TarchiveSource'};
  $sessionid    = $f->{'SessionID'};
  @pic_path     = split /_check/, $f->{'VALUE'};
  $jiv_header   = $pic_path[0] . ".header";
  $jiv_raw_byte = $pic_path[0] . ".raw_byte.gz";
  ($file, $dir, $ext) = fileparse($f->{'File'});
  $nii_file     = basename($file, ".mnc") . ".nii";
  @candid = split("/", $dir);
  if ($ARGV[0] eq "confirm") {
    # Let's make directories
    make_path($data_dir . "/archive/"     . $dir) unless(-d  $data_dir . "/archive/"     . $dir);
    make_path($data_dir . "/archive/pic/" . $candid[1]) unless(-d  $data_dir . "/archive/pic/" . $candid[1]);
    make_path($data_dir . "/archive/jiv/" . $candid[1]) unless(-d  $data_dir . "/archive/jiv/" . $candid[1]);

    if (-e $data_dir . "/" . $dir . $nii_file) {
      rename($data_dir . "/" . $dir . $nii_file, $data_dir . "/archive/" . $dir . $nii_file);
    }
    rename($data_dir . "/"     . $f->{'File'}, $data_dir . "/archive/" . $f->{'File'});
    rename($data_dir . "/pic/" . $f->{'VALUE'}, $data_dir . "/archive/pic/" . $f->{'VALUE'});
    rename($data_dir . "/jiv/" . $jiv_header, $data_dir . "/archive/jiv/" . $jiv_header);
    rename($data_dir . "/jiv/" . $jiv_raw_byte, $data_dir . "/archive/jiv/" . $jiv_raw_byte);
    print "\nMoving these files to archive:\n";
  } else {
    print "\nFiles that will be moved when rerunning the script using the confirm option:\n";
  }

  print $data_dir . "/"     . $f->{'File'} . "\n";
  if (-e $data_dir . "/"    . $dir . $nii_file) {
    print $data_dir . "/"   . $dir . $nii_file . "\n";
  }
  print $data_dir . "/pic/" . $f->{'VALUE'} . "\n";
  print $data_dir . "/jiv/" . $jiv_header . "\n";
  print $data_dir . "/jiv/" . $jiv_raw_byte . "\n";
}

print "\nDelete from DB";
# Delete from DB
selORdel("parameter_file","Value");
if ($delqcdata) {
  selORdel("files_qcstatus","QCStatus");
  selORdel("feedback_mri_comments","Comment");
}
# selORdel("mri_protocol_violated_scans","ID");  # if there is data here, the mnc will be in the trashbin
# selORdel("MRICandidateErrors","Reason");       # not applicable to /assembly
# selORdel("mri_violations_log","LogID");        # "

### Removal of entry in mri_acquisition_dates table ###
### (if only one file exists and is being removed,  ###
### the table entry needs to be removed)            ###
print "\nTarchiveID: $tarchiveid\n";
print "\nSessionID: $sessionid\n";


if ($seriesuid) {
  $val = $seriesuid;
  $field = "SeriesUID";
} else {
  $val = $fileid;
  $field = "FileID"
}
# Check #1 in files, if other files from same session
$query = "select * from files as g " .
"where g.SessionID IN (select f.SessionID from files as f where f.${field}=?) " .
"and g.${field} <> ?";

$sth = $dbh->prepare($query);
$rvl = $sth->execute($val, $val);

if ($sth->rows > 0) {
    $sessionfilesfound = 1;
    print "\nfiles found in the same session\n";
}

# Check #2 in mri_protocol_violated_scans
$query = "select * from mri_protocol_violated_scans as m " .
"WHERE m.SeriesUID in (SELECT t.SeriesUID FROM tarchive_series as t " .
"WHERE t.TarchiveID=?)";

$sth = $dbh->prepare($query);
$rvl = $sth->execute($tarchiveid);

if ($sth->rows > 0) {
    $sessionfilesfound = 1;
    print "\nfiles found in mri_protocol_violated_scans\n";
}


# Check #3 in MRICandidateErrors
$query = "SELECT * FROM MRICandidateErrors as m " .
"WHERE m.TarchiveID=?";

$sth = $dbh->prepare($query);
$rvl = $sth->execute($tarchiveid);

if ($sth->rows > 0) {
    $sessionfilesfound = 1;
    print "\nfiles found in MRICandidateErrors\n";
}


# Check #4 in mri_violations_log
$query = "SELECT * FROM mri_violations_log as m " .
"WHERE m.TarchiveID=?";

$sth = $dbh->prepare($query);
$rvl = $sth->execute($tarchiveid);

if ($sth->rows > 0) {
    $sessionfilesfound = 1;
    print "\nfiles found in mri_violations_log\n";
}


# If no related files were found, delete the entry
if (!$sessionfilesfound) {

  my $query = $selORdel . "FROM mri_acquisition_dates where SessionID=?";
  my $sth = $dbh->prepare($query);
  $sth->execute($sessionid);

  if ($selORdel eq "SELECT * ") {
    while (my $pf = $sth->fetchrow_hashref()) {
        print "\nAcquisitionDate: " . $pf->{'AcquisitionDate'};
    }
  } else {
    print "\nmri_acquisition_dates has been deleted\n";
  }

}

# If using SeriesUID, get number of matching files before deleting
if ($field eq "SeriesUID") {
    $query = "SELECT COUNT(*) FROM files WHERE SeriesUID = ?";
    $sth = $dbh->prepare($query);
    $sth->execute($seriesuid);
    $sUIDFiles = $sth->fetchrow_array;
    print "\n". $sUIDFiles ." files matched with SeriesUID " . $seriesuid . "\n";
}

# Delete file records last
selORdel("files","File");

# Update the number of minc inserted in mri_upload by subtracting one
if ($selORdel eq "DELETE ") {
    $query = "SELECT number_of_mincInserted FROM mri_upload " .
        "WHERE TarchiveID=?";

    $sth = $dbh->prepare($query);
    $sth->execute($tarchiveid);
    my $nmi = $sth->fetchrow_array;

    if ($sth->rows > 0) {
        if ($field eq "SeriesUID") {
            $nmi -= $sUIDFiles;
        } else {
            $nmi -= 1;
        }
        $query = "UPDATE mri_upload SET number_of_mincInserted=? ".
            "WHERE TarchiveID=?";

        $sth = $dbh->prepare($query);
        my $success = $sth->execute($nmi, $tarchiveid);

        if ($success) {
            print "\nNew count for number of mincs inserted changed to " . $nmi . "\n";
        }
    }
}


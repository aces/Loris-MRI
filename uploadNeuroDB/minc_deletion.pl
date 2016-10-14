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
my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.2 $
    =~ /: (\d+)\.(\d+)/;
my $profile   = '';      # this should never be set unless you are in a
                             # stable production environment
my $seriesuid = '';
my $fileid    = '';
my $sth;
my $rvl;
my $query     = '';
my $selORdel  = '';
my @opt_table = (
                 ["Basic options","section"],
                 ["-profile     ","string",1, \$profile,
                  "config file in ../dicom-archive/.loris_mri"
                 ],
                 ["-seriesuid", "string", 1, \$seriesuid, "Only deletes this SeriesUID"
                 ],
                 ["-fileid", "string", 1, \$fileid, "Only deletes this FileID"
                 ],
                 );


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
  - Deleting all related data from 4 database tables.
    parameter_file, files_qcstatus, feedback_mri_comments, files
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

my $data_dir         = $Settings::data_dir;
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);


sub selORdel {
  my ($table, $field) = @_;
  my $where = '';

  if ($seriesuid) {
    if ($table eq "parameter_file") {
      $where = " WHERE FileID = (SELECT FileID FROM files WHERE SeriesUID = ?)";
    } else {
      $where = " WHERE SeriesUID = ?";
    }
  } elsif ($fileid) {
    $where = " WHERE FileID =  ?";
  }


  my $query = $selORdel . "FROM " . $table . $where;
  my $sth = $dbh->prepare($query);
  if ($seriesuid) {
    $sth->execute($seriesuid);
  } elsif ($fileid) {
    $sth->execute($fileid);
  }

  if ($selORdel eq "SELECT * ") {
    if ($seriesuid) {
      $query =~ s/\?/'$seriesuid'/g;
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
         "pf.FileID = ";

# Useful database tracing for troubleshooting
# $dbh->trace(5);

if ($seriesuid) {
  $query .= "(SELECT FileID FROM files WHERE SeriesUID = ?)";
  $sth = $dbh->prepare($query);
  $rvl = $sth->execute($seriesuid);
} elsif ($fileid) {
  $query .= "?";
  $sth = $dbh->prepare($query);
  $rvl = $sth->execute($fileid);
}

if ($sth->err) {
  die "ERROR! return code:" . $sth->err . " error msg: " . $sth->errstr . "\n";
}

if (defined $rvl && $rvl == 0) {
  die "Can't rename if there is no value return from: \n" . $query . "\n";
}

my $f = $sth->fetchrow_hashref();

my $tarchiveid   = $f->{'TarchiveSource'};
my $sessionid    = $f->{'SessionID'};
my @pic_path     = split /_check/, $f->{'VALUE'};
my $jiv_header   = $pic_path[0] . ".header";
my $jiv_raw_byte = $pic_path[0] . ".raw_byte.gz";
my ($file, $dir, $ext) = fileparse($f->{'File'});
my $nii_file     = basename($file, ".mnc") . ".nii";
my @candid = split("/", $dir);

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
  print "Moving these files to archive:\n";
} else {
  print "Files that will be moved when rerunning the script using the confirm option:\n";
}

print $data_dir . "/"     . $f->{'File'} . "\n";
if (-e $data_dir . "/"    . $dir . $nii_file) {
  print $data_dir . "/"   . $dir . $nii_file . "\n";
}
print $data_dir . "/pic/" . $f->{'VALUE'} . "\n";
print $data_dir . "/jiv/" . $jiv_header . "\n";
print $data_dir . "/jiv/" . $jiv_raw_byte . "\n";

# Delete from DB
selORdel("parameter_file","Value");
selORdel("files_qcstatus","QCStatus");
selORdel("feedback_mri_comments","Comment");
# selORdel("mri_protocol_violated_scans","ID");  # if there is data here, the mnc will be in the trashbin
# selORdel("MRICandidateErrors","Reason");       # not applicable to /assembly
# selORdel("mri_violations_log","LogID");        # "
selORdel("files","File");

### Removal of entry in mri_acquisition_dates table ###
### (if only one file exists and is being removed,  ###
### the table entry needs to be removed)            ###
print "\nTarchiveID: $tarchiveid\n";
print "\nSessionID: $sessionid\n";

# Check #1 in files, if other files from same session
$query = "select * from files as g " .
"where g.SessionID=(select f.SessionID from files as f where f.SeriesUID=?) " .
"and g.SeriesUID <> ?";

$sth = $dbh->prepare($query);
$rvl = $sth->execute($seriesuid, $seriesuid);

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

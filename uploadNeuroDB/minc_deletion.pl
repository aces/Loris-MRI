#! /usr/bin/perl

=pod

=head1 NAME

minc_deletion.pl -- this script deletes files records from the database, and
deletes and archives the backend files stored in C</data/$PROJECT/data/assembly/>.
Files to be deleted can be specified either based on the series UID or the file
ID.

=head1 SYNOPSIS

perl minc_deletion.pl C<[options]>

Available options are:

-profile   : name of the config file in C<../dicom-archive/.loris_mri>

-series_uid: the series UID of the file to be deleted

-fileid    : the file ID of the file to be deleted


=head1 DESCRIPTION

This program deletes MINC files from LORIS by:
  - Moving the existing files (C<.mnc>, C<.nii>, C<.jpg>, C<.header>,
    C<.raw_byte.gz>) to the archive directory: C</data/$PROJECT/data/archive/>
  - Deleting all related data from C<parameter_file> & C<files> tables
  - Deleting data from C<files_qcstatus> and C<feedback_mri_comments>
    database tables if the C<-delqcdata> option is set. In most cases
    you would want to delete this when the images change
  - Deleting C<mri_acquisition_dates> entry if it is the last file
    removed from that session.

Users can use the argument C<select> to view the record that could be removed
from the database, or C<confirm> to acknowledge that the data in the database
will be deleted once the script executes.


=cut


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
use NeuroDB::ExitCodes;

my $sessionfilesfound = '';
my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.3 $
    =~ /: (\d+)\.(\d+)/;
my $profile   = '';      # this should never be set unless you are in a
                             # stable production environment
my $seriesuid = ''; # seriesUID value from script inputs
my $fileid    = ''; # fileID value from script inputs
my @files_FileID;   # fileID value from query of the files table
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

Deletes MINC files from LORIS by:
  - Moving the existing files (.mnc, .nii, .jpg, .header, .raw_byte.gz) to the
    archive directory: /data/\$PROJECT/data/archive/
  - Deleting all related data from parameter_file & files tables
  - Deleting data from files_qcstatus & feedback_mri_comments
    database tables if the -delqcdata option is set. In most cases
    you would want to delete this when the images change
  - Deleting mri_acquisition_dates entry if it is the last file
    removed from that session.

Users can use the argument "select" to view the record that could be removed
from the database, or "confirm" to acknowledge that the data in the database
will be deleted once the script executes.

Documentation: perldoc minc_deletion.pl

HELP
my $Usage = <<USAGE;
usage: $0 [options] select|confirm
       $0 -help to list options

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
if ( !$ARGV[0] ) {
    print $Help;
    print STDERR "\n\tERROR: You must type select or confirm.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
if (!$seriesuid && !$fileid) {
    print STDERR "\n\tERROR: You must specify either -seriesuid or -fileid "
                 . "option.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
if ($seriesuid && $fileid) {
    print STDERR " ERROR: You cannot specify both -seriesuid and -fileid "
                 . "options.\n\n";
    exit $NeuroDB::ExitCodes::INVALID_ARG;
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
$query = "select f.File, f.TarchiveSource, f.SessionID, pf.`VALUE`, f.FileID from files as f ".
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


my ($tarchiveid, $sessionid, @pic_path, $file, $dir, $ext, $nii_file, @candid);

while (my $f = $sth->fetchrow_hashref()) {
  $tarchiveid   = $f->{'TarchiveSource'};
  $sessionid    = $f->{'SessionID'};
  # grep the list of fileIDs from the files table and organize them so they
    # can be given in a "WHERE FileID IN ()" syntax
  push(@files_FileID, $f->{'FileID'});
  @pic_path     = split /_check/, $f->{'VALUE'};
  ($file, $dir, $ext) = fileparse($f->{'File'});
  $nii_file     = basename($file, ".mnc") . ".nii";
  @candid = split("/", $dir);
  if ($ARGV[0] eq "confirm") {
    # Let's make directories
    make_path($data_dir . "/archive/"     . $dir) unless(-d  $data_dir . "/archive/"     . $dir);
    make_path($data_dir . "/archive/pic/" . $candid[1]) unless(-d  $data_dir . "/archive/pic/" . $candid[1]);

    if (-e $data_dir . "/" . $dir . $nii_file) {
      rename($data_dir . "/" . $dir . $nii_file, $data_dir . "/archive/" . $dir . $nii_file);
    }
    rename($data_dir . "/"     . $f->{'File'}, $data_dir . "/archive/" . $f->{'File'});
    rename($data_dir . "/pic/" . $f->{'VALUE'}, $data_dir . "/archive/pic/" . $f->{'VALUE'});
    print "\nMoving these files to archive:\n";
  } else {
    print "\nFiles that will be moved when rerunning the script using the confirm option:\n";
  }

  print $data_dir . "/"     . $f->{'File'} . "\n";
  if (-e $data_dir . "/"    . $dir . $nii_file) {
    print $data_dir . "/"   . $dir . $nii_file . "\n";
  }
  print $data_dir . "/pic/" . $f->{'VALUE'} . "\n";
}

print "\nDelete from DB";
# Delete from DB

# Take care of the QC data
if (($delqcdata) || ($selORdel eq "SELECT * ")) {
  ## if the "-delqcdata" option is set or the script is run in "select" mode
    # executes queries in function selORdel (which will either "SELECT *" or
    # "DELETE" from table given as argument to the function selORdel
  selORdel("files_qcstatus","QCStatus");
  selORdel("feedback_mri_comments","Comment");
} else {
  ## if don't want to delete the QC data, will have to set their FileID to
    # null so that it can be remapped to the new FileID based on their
    # SeriesUID and echo time, and the FileID can be removed from the files
    # table
  foreach my $table ("files_qcstatus", "feedback_mri_comments") {
      (my $updateQCquery = <<QUERY) =~ s/\n//gm;
 UPDATE $table
 SET    FileID=NULL
 WHERE  FileID=?
QUERY
      $sth = $dbh->prepare($updateQCquery);
      $rvl = $sth->execute($_) for @files_FileID;
  }
}

# Delete from parameter_file
selORdel("parameter_file","Value");

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
  $field = "FileID";
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

exit $NeuroDB::ExitCodes::SUCCESS;

__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

Gregory Luneau,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut

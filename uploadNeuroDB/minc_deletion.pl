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

my $profile   = '';      # this should never be set unless you are in a
                             # stable production environment
my $seriesuid = '';
my $query     = '';
my $selORdel  = '';
my @opt_table = (
                 ["Basic options","section"],
                 ["-profile     ","string",1, \$profile,
                  "name of config file in ../dicom-archive/.loris_mri"
                 ],
                 ["-seriesuid", "string", 1, \$seriesuid, "Only deletes this SeriesUID"
                 ],
                 );

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
    print " ERROR: You must type select or confirm and have an ".
          "existing profile.\n\n";
    exit 3;  
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

  if ($table eq "parameter_file") {
    $where = " WHERE FileID = (SELECT FileID FROM files WHERE SeriesUID = ?)";
  } else {
    $where = " WHERE SeriesUID = ?";
  }

  my $query = $selORdel . "FROM " . $table . $where;
  print $query . "\n";
  my $sth = $dbh->prepare($query);
  $sth->execute($seriesuid);

  if ($selORdel eq "SELECT * ") {
    while (my $pf = $sth->fetchrow_hashref()) {
        print "\n$field: " . $pf->{$field};
    }
  }
}


# Delete from FS:
# /data/ibis/data_assembly/858677/V24/mri/native/ibis_858677_V24_dti_005.mnc
# /data/ibis/data/pic/858677/ibis_858677_V24_dti_005_43606_check.jpg
# /data/ibis/data/jiv

# get the file names
$query = "select f.File, pf.`VALUE` from files as f ".
         "left join parameter_file as pf using (FileID) where ".
         "pf.ParameterTypeID = (select pt.ParameterTypeID from parameter_type as pt where pt.Name = 'check_pic_filename') and ".
         "pf.FileID = (SELECT FileID FROM files WHERE SeriesUID = ?)";
my $sth = $dbh->prepare($query);
my $rvl = $sth->execute($seriesuid);

if ($sth->err) {
  die "ERROR! return code:" . $sth->err . " error msg: " . $sth->errstr . "\n";
}

if (defined $rvl && $rvl == 0) {
  die "Can't rename if there is no value return from: \n" . $query . "\n";
}

my $f = $sth->fetchrow_hashref();

my @pic_path     = split /_check/, $f->{'VALUE'};
my $jiv_header   = $pic_path[0] . ".header";
my $jiv_raw_byte = $pic_path[0] . ".raw_byte.gz";
my($file, $dir, $ext) = fileparse($f->{'File'});
my @candid = split("/", $dir);

# Let's make directories
make_path($data_dir . "/archive/"    . $dir) unless(-d  $data_dir . "/archive/"     . $dir);
make_path($data_dir . "/archive/pic/" . $candid[1]) unless(-d  $data_dir . "/archive/pic/" . $candid[1]);
make_path($data_dir . "/archive/jiv/" . $candid[1]) unless(-d  $data_dir . "/archive/jiv/" . $candid[1]);

if ($ARGV[0] eq "confirm") {
  rename($data_dir . "/" . $f->{'File'}, $data_dir . "/archive/" . $f->{'File'});
  rename($data_dir . "/pic/" . $f->{'VALUE'}, $data_dir . "/archive/pic/" . $f->{'VALUE'});
  rename($data_dir . "/jiv/" . $jiv_header, $data_dir . "/archive/jiv/" . $jiv_header);
  rename($data_dir . "/jiv/" . $jiv_raw_byte, $data_dir . "/archive/jiv/" . $jiv_raw_byte);
}

print "Moving these files to archive:\n";
print $data_dir . "/" . $f->{'File'} . "\n";
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

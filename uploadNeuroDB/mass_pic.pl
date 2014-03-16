#!/usr/bin/perl

use strict;
use FindBin;
use lib "$FindBin::Bin";
use Getopt::Tabular;
use NeuroDB::DBI;
use NeuroDB::File;
use NeuroDB::MRI;

# Set stuff for GETOPT
my $verbose    = 1;
my $profile    = undef;
my $minFileID  = undef;
my $maxFileID  = undef;
my $query;
my $debug       = 1;
my $Usage = "mass_pic.pl generates check pic images for NeuroDB for those
             files that are missing pics.
             \n\n See $0 -help for more info\n\n";

my @arg_table =
    (
     ["Database options", "section"],
     ["-profile","string",1, \$profile, "Specify the name of the    
       config file which resides in .neurodb in your home directory."],
     ["File control", "section"],
     ["-minFileID", "integer", 1, \$minFileID, "Specify the minimum FileID
       to operate on."], 
     ["-maxFileID", "integer", 1, \$maxFileID, "Specify the maximum FileID 
      to operate on."], 
     ["General options", "section"],
     ["-verbose", "boolean", 1,   \$verbose, "Be verbose."],
     );

GetOptions(\@arg_table, \@ARGV) ||  exit 1;

# checking for profile settings
if (-f "$ENV{HOME}/.neurodb/$profile") {
	{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
}
if ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' 
           in:  $ENV{HOME}/.neurodb/ \n\n"; 
    exit 33;
} 

if (!$profile) { 
    print $Usage; 
    print "\n\tERROR: You must specify an existing profile.\n\n";  
    exit 33;  
}

# where the pics should go
my $pic_dir = $Settings::data_dir . '/pic';

# establish database connection if database option is set
print "Connecting to database.\n" if $verbose;
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

## now go make the pics
$query = "SELECT \@checkPicID:=ParameterTypeID FROM parameter_type WHERE
          Name='check_pic_filename'";
$dbh->do($query);
if ($debug) {
    print $query . "\n";
}

$query = "CREATE TEMPORARY TABLE check_pic_filenames (FileID int(10) unsigned
          NOT NULL, Value text, PRIMARY KEY (FileID))";
$dbh->do($query);

if ($debug) {
    print $query . "\n";
}

$query = "INSERT INTO check_pic_filenames SELECT FileID, Value FROM 
          parameter_file WHERE ParameterTypeID=\@checkPicID AND     
          Value IS NOT NULL";
$dbh->do($query);

if ($debug) {
    print $query . "\n";
}

my $extraWhere = "";
$extraWhere .= " AND f.FileID >= $minFileID" if defined $minFileID;
$extraWhere .= " AND f.FileID <= $maxFileID" if defined $maxFileID;

$query = "SELECT f.FileID FROM files AS f LEFT OUTER JOIN check_pic_filenames
          AS c USING (FileID) WHERE c.FileID IS NULL AND f.FileType='mnc'
          $extraWhere";
if ($debug) {
    print $query . "\n";
}

my $sth = $dbh->prepare($query);
$sth->execute();

while(my $rowhr = $sth->fetchrow_hashref()) {
    print "$rowhr->{'FileID'}\n" if $verbose;
    my $file = NeuroDB::File->new(\$dbh);
    $file->loadFile($rowhr->{'FileID'});

    unless(&NeuroDB::MRI::make_pics(\$file, $Settings::data_dir, 
          $pic_dir, $Settings::horizontalPics)) {
        print "FAILURE!\n";
    }
}

$dbh->disconnect();

print "Finished\n" if $verbose;
exit 0;

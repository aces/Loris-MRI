#!/usr/bin/perl

use strict;
use FindBin;
use lib "$FindBin::Bin";
use Getopt::Tabular;
use NeuroDB::DBI;
use NeuroDB::File;
use NeuroDB::MRI;
################################################################
################## Set stuff for GETOPT ########################
################################################################
my $verbose    = 1;
my $profile    = undef;
my $minFileID  = undef;
my $maxFileID  = undef;
my $query;
my $debug       = 0;
my $Usage = "mass_pic.pl generates check pic images for NeuroDB for those ".
            "files that are missing pics. ".
            " \n\n See $0 -help for more info\n\n";

my @arg_table =
    (
         ["Database options", "section"],
         ["-profile","string",1, \$profile, "Specify the name of the ".   
          "config file which resides in ../dicom-archive/.loris_mri"],
         ["File control", "section"],
         ["-minFileID", "integer", 1, \$minFileID, 
          "Specify the minimum FileID to operate on."], 
         ["-maxFileID", "integer", 1, \$maxFileID, 
          "Specify the maximum FileID to operate on."], 
         ["General options", "section"],
         ["-verbose", "boolean", 1,   \$verbose, "Be verbose."],
    );

GetOptions(\@arg_table, \@ARGV) ||  exit 1;

################################################################
################ checking for profile settings #################
################################################################
if (-f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
	{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
}
if ($profile && !@Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' ". 
          "in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; 
    exit 33;
} 

if (!$profile) { 
    print $Usage; 
    print "\n\tERROR: You must specify an existing profile.\n\n";  
    exit 33;  
}

################################################################
# Where the pics should go #####################################
################################################################
my $pic_dir = $Settings::data_dir . '/pic';

################################################################
# Establish database connection if database option is set ######
################################################################
print "Connecting to database.\n" if $verbose;
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

################################################################
##### Now go make the pics #####################################
################################################################
($query = <<QUERY) =~ s/\n/ /gm;
    SELECT 
        \@checkPicID:=ParameterTypeID 
    FROM 
        parameter_type 
    WHERE
        Name=?
QUERY
my $sth = $dbh->prepare($query);
$sth->execute('check_pic_filename');
if ($debug) {
    print $query . "\n";
}

($query = <<QUERY) =~ s/\n/ /gm; 
    CREATE TEMPORARY TABLE check_pic_filenames 
        (FileID int(10) unsigned NOT NULL, 
         Value text, 
         PRIMARY KEY (FileID)
        )
QUERY
$sth = $dbh->prepare($query);
$sth->execute();

if ($debug) {
    print $query . "\n";
}

($query = <<QUERY) =s/\n/ /gm; 
    INSERT INTO check_pic_filenames 
        SELECT 
            FileID, 
            Value 
        FROM 
            parameter_file 
        WHERE 
            ParameterTypeID=\@checkPicID 
            AND Value IS NOT NULL
QUERY
$sth = $dbh->prepare($query);
$sth->execute();

if ($debug) {
    print $query . "\n";
}

($query = <<QUERY) =~ s/\n/ /gm; 
    SELECT f.FileID 
    FROM 
        files AS f 
        LEFT OUTER JOIN check_pic_filenames AS c USING (FileID) 
    WHERE 
        c.FileID IS NULL 
        AND f.FileType=?
QUERY

# Complete query if min and max File ID have been defined.
$query .= " AND f.FileID <= ?" if defined $maxFileID;
$query .= " AND f.FileID <= ?" if defined $minFileID;

# Create array of parameters to use for query.
my @param = ('mnc');
push (@param, $maxFileID) if defined $maxFileID;
push (@param, $minFileID) if defined $minFileID;

if ($debug) {
    print $query . "\n";
}

# Execute query
$sth = $dbh->prepare($query);
$sth->execute(@param);

while(my $rowhr = $sth->fetchrow_hashref()) {
    print "$rowhr->{'FileID'}\n" if $verbose;
    my $file = NeuroDB::File->new(\$dbh);
    $file->loadFile($rowhr->{'FileID'});

    unless(
        &NeuroDB::MRI::make_pics(
            \$file, $Settings::data_dir, 
            $pic_dir, $Settings::horizontalPics
        )
    ) {
        print "FAILURE!\n";
    }
}

$dbh->disconnect();

print "Finished\n" if $verbose;
exit 0;

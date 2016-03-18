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

my $Usage = "mass_jiv.pl generates JIV images for NeuroDB for those files that are missing JIVs.
\n\n See $0 -help for more info\n\n";

my @arg_table =
    (
     ["Database options", "section"],
     ["-profile","string",1, \$profile, "Specify the name of the config file which resides in ../dicom-archive/.loris_mri"],

     ["File control", "section"],
     ["-minFileID", "integer", 1, \$minFileID, "Specify the minimum FileID to operate on."], 
     ["-maxFileID", "integer", 1, \$maxFileID, "Specify the maximum FileID to operate on."], 

     ["General options", "section"],
     ["-verbose", "boolean", 1,   \$verbose, "Be verbose."],
     );

GetOptions(\@arg_table, \@ARGV) ||  exit 1;

# checking for profile settings
if(-f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
	{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
}
if ($profile && !@Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; exit 33;
} 

if(!$profile) { print $Usage; print "\n\tERROR: You must specify an existing profile.\n\n";  exit 33;  }

# where the JIVs should go
my $jiv_dir = $Settings::data_dir . '/jiv';

# establish database connection if database option is set
print "Connecting to database.\n" if $verbose;
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);


## now go make the jivs
(my $selectquery = <<QUERY) =~ s/\n/ /gm;
    SELECT
        \@jivPathID:=ParameterTypeID
    FROM
        parameter_type
    WHERE 
        Name=?
QUERY
my $selectsth = $dbh->prepare($selectquery);
$selectsth->execute('jiv_path');
(my $createtmpquery = <<QUERY) =~ s/\n/ /gm;
    CREATE TEMPORARY TABLE jiv_paths
        (FileID int(10) unsigned NOT NULL, 
         Value text, 
         PRIMARY KEY (FileID)
        )
QUERY
my $createtmpsth = $dbh->prepare($createtmpquery);
$createtmpsth->execute();
(my $insertquery = <<QUERY) =~ s/\n/ /gm;
    INSERT INTO jiv_paths
        SELECT 
            FileID, 
            Value 
        FROM 
            parameter_file 
        WHERE 
            ParameterTypeID=\@jivPathID 
            AND Value IS NOT NULL
QUERY
my $insertsth = $dbh->prepare($insertquery);
$insertsth->execute();

(my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT
        f.FileID, 
        File
    FROM
        files AS f
        LEFT OUTER JOIN jiv_paths AS j USING (FileID)
    WHERE 
        j.FileID IS NULL 
        AND f.FileType=?
QUERY

# Complete query if min and max File ID have been defined.
$query .= " AND f.FileID <= ?" if defined $maxFileID;
$query .= " AND f.FileID <= ?" if defined $minFileID;

# Create array of parameters to use for query.
my @param = ('mnc');
push (@param, $maxFileID) if defined $maxFileID;
push (@param, $minFileID) if defined $minFileID;

# Execute query
my $sth = $dbh->prepare($query);
$sth->execute(@param);

while(my $rowhr = $sth->fetchrow_hashref()) {
    print "$rowhr->{'FileID'}\n" if $verbose;

    unless( -e $rowhr->{'File'} and -f $rowhr->{'File'}) {
	print "MISSING MINC ($rowhr->{'FileID'}) $rowhr->{'File'}\n";
	next;
    }

    my $file = NeuroDB::File->new(\$dbh);
    $file->loadFile($rowhr->{'FileID'});

    unless(&NeuroDB::MRI::make_jiv(\$file, $Settings::data_dir, $jiv_dir)) {
	print "FAILURE!\t$rowhr->{'FileID'}\n";
    }
}

$dbh->disconnect();

print "Finished\n" if $verbose;
exit 0;


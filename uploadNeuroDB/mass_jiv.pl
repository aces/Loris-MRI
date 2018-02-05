#!/usr/bin/perl

use strict;
use FindBin;
use lib "$FindBin::Bin";
use Getopt::Tabular;
use NeuroDB::DBI;
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::ExitCodes;


# Set stuff for GETOPT
my $verbose    = 0;
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

GetOptions(\@arg_table, \@ARGV) ||  exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

# checking for profile settings
if ( !$profile ) {
    print $Help;
    print "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
if(-f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
	{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
}
if ( !@Settings::db ) {
    print "\n\tERROR: You don't have a @db setting in the file "
          . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;}


# establish database connection if database option is set
print "Connecting to database.\n" if $verbose;
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# where the JIVs should go
my $data_dir = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'dataDirBasepath'
                    );
my $jiv_dir = $data_dir . '/jiv';


## now go make the jivs
$dbh->do("SELECT \@jivPathID:=ParameterTypeID FROM parameter_type WHERE Name='jiv_path'");
$dbh->do("CREATE TEMPORARY TABLE jiv_paths (FileID int(10) unsigned NOT NULL, Value text, PRIMARY KEY (FileID))");
$dbh->do("INSERT INTO jiv_paths SELECT FileID, Value FROM parameter_file WHERE ParameterTypeID=\@jivPathID AND Value IS NOT NULL");

my $extraWhere = "";
$extraWhere .= " AND f.FileID >= $minFileID" if defined $minFileID;
$extraWhere .= " AND f.FileID <= $maxFileID" if defined $maxFileID;

my $sth = $dbh->prepare("SELECT f.FileID, File FROM files AS f LEFT OUTER JOIN jiv_paths AS j USING (FileID) WHERE j.FileID IS NULL AND f.FileType='mnc' $extraWhere");
$sth->execute();

while(my $rowhr = $sth->fetchrow_hashref()) {
    print "$rowhr->{'FileID'}\n" if $verbose;

    unless( -e $rowhr->{'File'} and -f $rowhr->{'File'}) {
	print "MISSING MINC ($rowhr->{'FileID'}) $rowhr->{'File'}\n";
	next;
    }

    my $file = NeuroDB::File->new(\$dbh);
    $file->loadFile($rowhr->{'FileID'});

    unless(&NeuroDB::MRI::make_jiv(\$file, $data_dir, $jiv_dir)) {
	print "FAILURE!\t$rowhr->{'FileID'}\n";
    }
}

$dbh->disconnect();

print "\n Finished mass_jiv.pl execution\n" if $verbose;
exit $NeuroDB::ExitCodes::SUCCESS;


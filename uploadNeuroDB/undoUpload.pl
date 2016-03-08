#!/usr/bin/perl 
# J-Sebastian Muehlboeck

use strict;
use Getopt::Tabular;       
use FindBin;

use lib "$FindBin::Bin";
use NeuroDB::File;
use NeuroDB::DBI;
use Data::Dumper;

# Turn on autoflush for standard output buffer 
$|++;

my ($CandID, $PSCID);
my $verbose = 1;
my $nuke    = 0;
my $visit   = undef;
my $profile = undef;


my $Help = <<HELP;

WHAT THIS IS:

-- Tool to delete MRI sessions and related entries from the NeuroDB database for a given CandID, visit and PSCID --

Usage:\n\t $0 CandID [ -visit VisitNum -pscid PSCID ]  [options]
\n\n See $0 -help for more info\n\n

HELP

my @arg_table =
    (
     ["Main options","section"],
     ["-profile","string",1, \$profile, "name of config file in ../dicom-archive/.loris_mri"],
     ["-visit","string",1, \$visit, "Visit number. You have to specify it!"],
     ["General options", "section"],
     ["-verbose","boolean",1, \$verbose, "Be verbose."],
     ["-nuke","boolean",1, \$nuke, "Actually delete the entries."],
     );

my $Usage = <<USAGE;
usage: $0 <FileID> [options]
       $0 -help to list options

USAGE
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@arg_table, \@ARGV) || exit 1;


# input option error checking
if(!defined($profile)) { print "\n\tERROR: You must specify a profile \n\n"; exit 33; }
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if (!@Settings::db) { print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; exit 33; }
if (!$visit) { print "\n\tThe flag : \'-visit\' is not optional!\n\n"; exit 1; }

if(scalar(@ARGV) != 1) { print $Usage; exit 1; }
$CandID = $ARGV[0];

# establish database connection and query for affected files 
my $dbh = NeuroDB::DBI::connect_to_db(@Settings::db);
(my $query = <<QUERY) =~ s/\n/ /gm; 
    SELECT 
        FileID, 
        file, 
        s.ID
    FROM 
        session AS s, 
        files AS f 
    WHERE 
        f.sessionID=s.ID 
        AND s.visit_label=? 
        AND s.CandID=? 
        AND f.outputtype=?
QUERY
my $sth = $dbh->prepare($query);
$sth->execute($dbh->quote($visit), $dbh->quote($CandID), 'native');
my $SelectedFiles = $sth->fetchall_arrayref();

# figure out the corresponding CandID
(my $query = <<QUERY) =~ s/\n/ /gm; 
    SELECT 
        PSCID 
    FROM 
        candidate 
    WHERE 
        CandID=?
QUERY
my $sth = $dbh->prepare($query);
$sth->execute($CandID);
$PSCID = $sth->fetchrow_array();
print "The corresponding Patient ID is : $PSCID \n";

my $fileCount = @$SelectedFiles;
if ($fileCount == 0) {print "\n\nNo MRI file sessions found. Nothing to be deleted!\n\n"; exit; }

# get rid of all file related entries
my ($fileID,$file,$session);
foreach my $row (@$SelectedFiles) {
    ($fileID, $file, $session) = @$row;
    print "$session, $fileID, $file \n";
    if ($nuke) {
        # delete from feedback_mri_comments
        ($query = <<QUERY) =~ s/\n/ /gm;
    DELETE FROM
        feedback_mri_comments
    WHERE
        FileID=?
QUERY
        print $query . "\n";
        $sth = $dbh->prepare($query);
        $sth->execute($fileID);

        # delete from parameter_file 
        ($query = <<QUERY) =~ s/\n/ /gm;
    DELETE FROM
        parameter_file
    WHERE
        FileID=?
QUERY
        print $query . "\n";
        $sth = $dbh->prepare($query);
        $sth->execute($fileID);

        # delete from files
        ($query = <<QUERY) =~ s/\n/ /gm;
    DELETE FROM
        files
    WHERE
        FileID=?
QUERY
        print $query . "\n";
        $sth = $dbh->prepare($query);
        $sth->execute($fileID);
        print "I should remove this file : $file\n";
        if (!-e $file) { 
            print $file . " does not exist!\n";
		 } else { 
            `rm -f $file` 
         }
	} 
}
# get rid of session related entries and finally the session itself.
if ($nuke) {
    # delete from feedback_mri_comments
    ($query = <<QUERY) =~ s/\n/ /gm;
    DELETE FROM 
        feedback_mri_comments
    WHERE
        SessionID=?
QUERY
    print $query . "\n";
    $sth = $dbh->prepare($query);
    $sth->execute($session);

    # delete from mri_acquisition_dates
    ($query = <<QUERY) =~ s/\n/ /gm;
    DELETE FROM 
        mri_acquisition_dates 
    WHERE
        SessionID=?
QUERY
    print $query . "\n";
    $sth = $dbh->prepare($query);
    $sth->execute($session);
    
    # delete from session
    ($query = <<QUERY) =~ s/\n/ /gm;
    DELETE FROM 
        session 
    WHERE
        SessionID=?
QUERY
    print $query . "\n";
    $sth = $dbh->prepare($query);
    $sth->execute($session);
    
    # update tarchive table 
    ($query = <<QUERY) =~ s/\n/ /gm;
    UPDATE 
        tarchive 
    SET
        SessionID=NULL
    WHERE
        SessionID=?
QUERY
    print $query . "\n";
    $sth = $dbh->prepare($query);
    $sth->execute($session);
}

if ($PSCID) && ($nuke) {
    print "Clearing notification Spool.\n";
    ($query = <<QUERY) =~ s/\n/ /gm;
    DELETE FROM 
        notification_spool 
    WHERE 
        Message LIKE ?
QUERY
    $sth = $dbh->prepare($query);
    $sth->execute('%${PSCID}%');
}



#!/usr/bin/perl 
# J-Sebastian Muehlboeck 2006
# sebas@bic.mni.mcgill.ca
# Perl tool based on DCMSUM.pm and DICOM.pm to create a summary report for a given dir containing dicoms
# @VERSION : $Id: dicomSummary.pl 4 2007-12-11 20:21:51Z jharlap $

=pod

=head1 NAME

dicomSummary.pl -- prints out an informative summary for DICOMs in a given directory

=head1 SYNOPSIS

perl dicomSummary.pl </PATH/TO/DICOM/DIR> [ -compare </PATH/TO/DICOM/COMPARE/DIR> ] [ -tmp </PATH/TO/TMP/DIR> ] `[options]`

Available options are:

-comparedir: path to another DICOM directory to compare with

-dbcompare : run a comparison with entries int he database

-database  : use the database

-dbreplace : use this option only if the DICOM data changed and need to be updated
             in the database

-profile   : specify the name of the config file residing in C<.loris_mri> of the
             current directory

-tmp       : to specify a temporary directory. It will contain the summaries if
             used with -noscreen option

-xdiff     : to see with tkdiff the result of the two folders comparison or the
             comparison with the database content with

-batch     : run in batch mode if set. Will log differences to a /tmp/diff.log file.

-verbose   : be verbose if set

-version   : print CVS version number and exit


=head1 DESCRIPTION

A tool for producing an informative summary for DICOMs in a given directory
(scanner information, acquisitions list, acquisitions parameters...). This tool
can also compare the DICOM data present in two directories or compare the DICOM
data present in a given directory with what is stored in the database.


=head2 METHODS

=cut

use strict;
use Cwd qw/ abs_path /;
use FindBin;
use Getopt::Tabular;
use FileHandle;

use lib "$FindBin::Bin";
use DICOM::DICOM;
use DICOM::DCMSUM;
use NeuroDB::DBI;

my $screen   = 1;
my $verbose  = 0;
my $produce  = "summary";
my $profile = undef;
my $xdiff    = 0;
my $version  = 0;
my $versionInfo = sprintf "%d", q$Revision: 4 $ =~ /: (\d+)/;
my $diff;

################################
# array of dicom dirs
my @dcmDirs;

# Declare vars for GETOPT
my ($compare ,$dcm_folder, $databasecomp, $dbase, $dbreplace, $temp, $batch);

my $Usage = "------------------------------------------

  Author    :        J-Sebastian Muehlboeck
  Date      :        2006/10/01
  Version   :        $versionInfo


WHAT THIS IS:

- a NON-INVASIVE tool ... it doesn't modify anything... just looks
- a tool for producing an informative summary for dicoms in a given directory
- a quick way to get an idea on what there is for a given subject
- a quick way to obtain information about the suject, scanner and acquisition parameters
- a quick way of listing all acquisitions aquired for a given subject 
- a convenient way to compare two directories in terms of the dicom data they contain... 
  or the contents of a directory with a database repository 

Usage:\n\t $0 </PATH/TO/DICOM/DIR> [ -compare </PATH/TO/DICOM/COMPARE/DIR> ] [ -tmp </PATH/TO/TMP/DIR> ] [options]
\n\n See $0 -help for more info\n\n";

my @arg_table =
    (
     ["Main options","section"],
     ["-comparedir","string",1, \$compare, "Enter the PATH to the directory you want to compare to the above."],
     ["-dbcompare","boolean",1, \$databasecomp, "Compare with database. Will only work if you actually archived your data using a database."],
     ["-database","boolean", 1, \$dbase, "Use a database if you have one set up for you. Just trying will fail miserably"],
     ["-dbreplace","boolean",1, \$dbreplace, "Use this option only if your dicom data changed and you want to re-insert the new summary"],
     ["-profile","string",1, \$profile, "Specify the name of the config file which resides in .loris_mri in the current directory."],

     
     ["Output options", "section"],
     ["-screen","boolean",1,    \$screen, "Print output to the screen."],
     # fixme add more options based on the capabilities of the DCMSUM class
     # ["-produce","string",1,    \$produce, "Default is summary, other options are header, files, and acquisitions"],
     ["-tmp","string",1,        \$temp, "You may specify a tmp dir. It will contain the summaries, if you use -noscreen"],
     ["-xdiff","boolean",1,     \$xdiff, "You are comparing two folders or with the database and you want to see the result with tkdiff."],
     ["-batch","boolean",1,     \$batch, "Run in batchmode. Will log differences to a /tmp/diff.log"],
     
     ["General options", "section"],
     ["-verbose","boolean",1,  \$verbose, "Be verbose."],
     ["-version","boolean",1,  \$version, "Print version and revision number and exit"],
     );

GetOptions(\@arg_table, \@ARGV) || exit 1;

# print version info and quit
if ($version) { print "$versionInfo\n"; exit; }

# checking for profile settings
if($profile && -f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") { { package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" } }    
if ($profile && !@Settings::db) { print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; exit 33; }


# basic error checking on dcm dir
if(scalar(@ARGV) != 1) { print $Usage; exit 1; } $dcm_folder = abs_path($ARGV[0]); if (!-d $dcm_folder) { print $Usage; exit 1; }
# basic checking for compare dir
if ($compare && !-d $compare) { print $Usage; exit 1; } if ($compare) { $compare = abs_path($compare); }

# Some combinations are just not possible
if ($xdiff || $compare || $batch || $databasecomp || $dbase){ $screen = undef; } elsif (!$compare || !$databasecomp) { $xdiff = undef; }

# you can't compare with db and a dir at the same time
if (($compare || $databasecomp) && $dbase) { print $Usage; 
    print "\t Please consider that some option combinations do not make sense. \n\n"; exit 1;
}
# get rid of the trailing slash of all given input dirs
$dcm_folder =~ s/^(.*)\/$/$1/; $temp =~ s/^(.*)\/$/$1/ unless (!$temp); $compare =~ s/^(.*)\/$/$1/ unless (!$compare);

# The specified dicom dir is the first dir in the dcmDirs array
push @dcmDirs, $dcm_folder; if ($compare) { push @dcmDirs, $compare; } # if compare is set

# This will make sure that a user specified tmp dir does exist and is writeable
my $TmpDir = $temp || "/tmp";  if (! -e $TmpDir) { print "This is not a valid tmp dir choice: \n".$!; exit 2; } 
elsif(! -w $TmpDir) { print "Sorry you have no permission to use $TmpDir as tmp dir\n"; exit 2; }

# establish database connection if database option is set
my $dbh;
if ($dbase) { $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db); print "Testing for database connectivity. \n" if $verbose; $dbh->disconnect(); print "Database is available.\n\n" if $verbose; }

####################### main ########################################### main ########################################### 

my $count = 0;
my ($studyUnique, $metaname, @metaFiles, $dcmdir, $sumTypeVersion);

# this silly header will only show, if you choose to send your output to the screen.    
if ($screen){ &silly_head(); }

foreach $dcmdir (@dcmDirs) {
    $count ++;
    if ($TmpDir && !$screen || $dbase) {
        my $metafile = "$TmpDir/tmp.meta";
	open META, ">$metafile";
	META->autoflush(1);
	select(META);
    }

# create new summary object
    my $summary = DICOM::DCMSUM->new($dcmdir,$TmpDir);
# determine the name for the summary file
    $metaname = $summary->{'metaname'};
# get the summary type version
    $sumTypeVersion = $summary->{'sumTypeVersion'};
# get the unique study ID
    $studyUnique = $summary->{'studyuid'};

# print the summary
    $summary->dcmsummary();
    
# If output went to a meta file, rename it and give it a count if -compare was specified.     
    if (!$screen) {
	close META;
	my $newName;
	if ($compare) { $newName = "$TmpDir/$metaname"."_"."$count.meta"; }
	else { $newName = "$TmpDir/$metaname.meta"; }
	my $move = "mv $TmpDir/tmp.meta $newName";
	push @metaFiles, $newName;
	`$move`;
    }
# Print to stout again          
    select (STDOUT);
    print "Done with $metaname\n" if $verbose;

# if -dbase has been given create an entry based on unique studyID
# Create database entry checking for already existing entries...
    if ($dbase) {
	$dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
	my $update = 1 unless !$dbreplace;
	$summary->database($dbh, $metaname, $update);
	print "\nDone dicomSummary.pl execution\n" if $verbose;
	exit;
    }
}

# END OF LOOP #######################################################################################

my $returnVal = 0;
    
# if -databasecompare has been given look for an entry based on unique studyID
if ($databasecomp) {
    my $conflict = &version_conflict($studyUnique);
    if ($conflict) { print "\n\n\tWARNING: You are using Version: $versionInfo but archived with Version : $conflict\n\n"; }
    $metaFiles[1] = &read_db_metadata($studyUnique);
    if (!$metaFiles[1]) { print "\nYou never archived this study or you are looking in the wrong database.\n\n"; exit; }
    if ($xdiff) { $diff = "tkdiff $metaFiles[0] $metaFiles[1]"; `$diff`; }
    else { 
	$diff = "diff -q $metaFiles[0] $metaFiles[1]"; 
	my $Comp = `$diff`;
	if ($Comp ne "") { print "There are differences\n" if $verbose; $returnVal = 99; }
	else { print "Comparing $dcm_folder with the database returned no differences. Smile :)\n" if $verbose; }
    }
}
# if comparing to another directory in non batch mode
if ($compare && !$batch) {
    $diff = "tkdiff $metaFiles[0] $metaFiles[1]";
    `$diff` if $xdiff;
}
# in batch mode you don't want any window to pop up. Just create a difference log in tmp
if ($batch && $metaFiles[1] && $returnVal == 99) {
    $diff = "diff -q  $metaFiles[0] $metaFiles[1] >> $TmpDir/difference.log";
    `mv $metaFiles[1]$metaFiles[0].'dbdiff'`;
    print "appending differences to $TmpDir/difference.log\n" if $verbose;
    `$diff`;
    `mv $metaFiles[1] $metaFiles[0].'dbdiff'`;
}

exit $returnVal;

######################################################################### end main ####################

=pod

=head3 read_db_metadata($StudyUID)

Accesses the database and gets the path of the file containing the metadata for
the given StudyUID.

INPUT: the DICOM Study Instance UID (StudyUID)

RETURNS: the path of the file containing the metadata for the given StudyUID or
         undef if none is found.

=cut

sub read_db_metadata {
# establish database connection if database option is set
    my $dbh;
    my $StudyUID = shift;
    my $dbmeta;
    my $dbcomparefile;
    $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
    print "Getting data from database.\n" if $verbose;
    (my $query = <<QUERY) =~ s/\n/ /gm;
SELECT 
  AcquisitionMetadata
FROM
  tarchive
WHERE
  DicomArchiveID=?
QUERY
    my $sth = $dbh->prepare($query);
    $sth->execute($StudyUID);
    if($sth->rows > 0) {
	my @row = $sth->fetchrow_array();
	$dbmeta = $row[0];
	$dbcomparefile = "$TmpDir/dbcompare.meta";
	open(DBDATA,">$dbcomparefile") || die ("Cannot Open File");
	print DBDATA "$dbmeta"; 
	close(DBDATA);
        return $dbcomparefile;
    }
    else { return undef; }
}

=pod

=head3 version_conflict($StudyUID)

Compares DICOM summary version numbers for a given StudyUID.

INPUT: the DICOM Study Instance UID (StudyUID)

RETURNS: the version number of the DICOM summary found in the database if the
         version is different from the current version of the script, 0 otherwise

=cut

sub version_conflict {
# establish database connection if database option is set
    my $dbh;
    my $StudyUID = shift;
    my $AVersion;
    my $NowVersion = $sumTypeVersion;
    $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
    (my $query = <<QUERY) =~ s/\n/ /gm;
SELECT
  sumTypeVersion
FROM
  tarchive
WHERE
  DicomArchiveID=?
QUERY
    my $sth = $dbh->prepare($query);
    $sth->execute($StudyUID);
    my @row = $sth->fetchrow_array();
    $AVersion = $row[0];
    if ($AVersion ne $NowVersion) { return $AVersion; }
    else { return 0; }
}

=pod

=head3 silly_head()

Print out a header to the DICOM summary.

=cut

sub silly_head {
    print  <<HEAD;
* * * * * * * * * * * * * *
                      _   
 _|* _  _  _ _   * _ |_ _ 
(_]|(_ (_)[ | )  |[ )| (_)
                          
HEAD
}


=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

J-Sebastian Muehlboeck,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut












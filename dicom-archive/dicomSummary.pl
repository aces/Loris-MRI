#!/usr/bin/perl
# J-Sebastian Muehlboeck 2006
# sebas@bic.mni.mcgill.ca
# Perl tool based on DCMSUM.pm and DICOM.pm to create a summary report for a given dir containing dicoms
# @VERSION : $Id: dicomSummary.pl 4 2007-12-11 20:21:51Z jharlap $

=pod

=head1 NAME

dicomSummary.pl -- prints out an informative summary for DICOMs in a given directory

=head1 SYNOPSIS

perl dicomSummary.pl </PATH/TO/DICOM/DIR> [ -comparedir </PATH/TO/DICOM/COMPARE/DIR> ] [ -tmp </PATH/TO/TMP/DIR> ] `[options]`

Available options are:

-comparedir: path to another DICOM directory to compare with (implies -xdiff)


-database  : use the database

-dbreplace : use this option only if the DICOM data changed and need to be updated
             in the database

-profile   : specify the name of the config file residing in the config directory

-tmp       : to specify a temporary directory. It will contain the summaries if
             used with -noscreen option

-xdiff     : to see with sdiff the result of the two folders comparison or the
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
use NeuroDB::ExitCodes;

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
my ($compare, $dcm_folder, $dbase, $dbreplace, $temp, $batch);

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

Usage:\n\t $0 </PATH/TO/DICOM/DIR> [ -comparedir </PATH/TO/DICOM/COMPARE/DIR> ] [ -tmp </PATH/TO/TMP/DIR> ] [options]
\n\n See $0 -help for more info\n\n";

my @arg_table =
    (
     ["Main options","section"],
     ["-comparedir","string",1, \$compare, "Enter the PATH to the directory you want to compare to the above."],
     ["-database","boolean", 1, \$dbase, "Use a database if you have one set up for you. Just trying will fail miserably"],
     ["-dbreplace","boolean",1, \$dbreplace, "Use this option only if your dicom data changed and you want to re-insert the new summary"],
     ["-profile","string",1, \$profile, "Specify the name of the config file which resides in the config directory."],


     ["Output options", "section"],
     ["-screen","boolean",1,    \$screen, "Print output to the screen."],
     # fixme add more options based on the capabilities of the DCMSUM class
     # ["-produce","string",1,    \$produce, "Default is summary, other options are header, files, and acquisitions"],
     ["-tmp","string",1,        \$temp, "You may specify a tmp dir. It will contain the summaries, if you use -noscreen"],
     ["-xdiff","boolean",1,     \$xdiff, "You are comparing two folders or with the database and you want to see the result with sdiff."],
     ["-batch","boolean",1,     \$batch, "Run in batchmode. Will log differences to a /tmp/diff.log"],

     ["General options", "section"],
     ["-verbose","boolean",1,  \$verbose, "Be verbose."],
     ["-version","boolean",1,  \$version, "Print version and revision number and exit"],
     );

GetOptions(\@arg_table, \@ARGV) || exit 1;

# print version info and quit
if ($version) { print "$versionInfo\n"; exit; }

# checking for profile settings
if($profile && -f "$ENV{LORIS_CONFIG}/$profile") { { package Settings; do "$ENV{LORIS_CONFIG}/$profile" } }
if ($profile && !@Settings::db) { print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/ \n\n"; exit 33; }


# basic error checking on dcm dir
if(scalar(@ARGV) != 1) { print $Usage; exit 1; } $dcm_folder = abs_path($ARGV[0]); if (!-d $dcm_folder) { print $Usage; exit 1; }
# basic checking for compare dir
if ($compare && !-d $compare) { print $Usage; exit 1; } if ($compare) { $compare = abs_path($compare); }

if ($compare && !$profile) {
    print "-profile must be used with the -database option. Aborting.\n";
    exit $NeuroDB::ExitCodes::INVALID_ARG;
}

# Some combinations are just not possible
if ($xdiff || $compare || $batch || $dbase) { $screen = undef; } elsif (!$compare) { $xdiff = undef; }

# you can't compare with db and a dir at the same time
if ($compare && $dbase) { print $Usage;
    print "\t Please consider that some option combinations do not make sense. \n\n"; exit 1;
}

# If -comparedir was used, -xdiff is turned on automatically
$xdiff = 1 if $compare;

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

# if comparing to another directory in non batch mode
if ($compare && !$batch) {
    $diff = "sdiff $metaFiles[0] $metaFiles[1]";
    system($diff) if $xdiff;
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

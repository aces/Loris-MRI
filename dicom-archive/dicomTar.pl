#!/usr/bin/perl
# J-Sebastian Muehlboeck 2006
# sebas@bic.mni.mcgill.ca
# Archive your dicom data using DICOM::DCMSUM 
# Tar and gzip dicom files and retar them with pertaining summary and creation log
# @VERSION : $Id: dicomTar.pl 9 2007-12-18 22:26:00Z jharlap $

=pod

=head1 NAME

dicomTar.pl -- archives DICOM data into the LORIS database

=head1 SYNOPSIS

perl dicomTar.pl </PATH/TO/SOURCE/DICOM> </PATH/TO/TARGET/DIR> `[options]`

Available options are:

-today                  : Use today's date for archive name instead of using
                          acquisition date

-database               : Use a database if you have one set up for you.
                          Just trying will fail miserably

-mri_upload_update      : Update the C<mri_upload> table by inserting the
                          correct C<tarchiveID>

-clobber                : Use this option only if you want to replace the
                          resulting tarball!

-profile                : Specify the name of the config file which resides in
                          C<.loris_mri> in the current directory

-centerName             : Specify the symbolic center name to be stored
                          alongside the DICOM institution

-verbose                : Be verbose if set

-version                : Print CVS version number and exit


=head1 DESCRIPTION

A tool for archiving DICOM data. Point it to a source directory and provide a
target directory which will be the archive location.

- If the source contains only one valid STUDY worth of DICOM it will create a
  descriptive summary, a (gzipped) DICOM tarball. The tarball with the metadata
  and a logfile will then be retarred into the final C<tarchive>.

- MD5 sums are reported for every step.

- It can also be used with a MySQL database.

=head2 Methods

=cut

use strict;
use FindBin;
use Getopt::Tabular;
use FileHandle;
use File::Basename;
use Cwd qw/ abs_path /;
use Socket;
use Sys::Hostname;
use lib "$FindBin::Bin";

use DICOM::DCMSUM;
use NeuroDB::DBI;
use NeuroDB::ExitCodes;


# version info from cvs
my $version = 0;
my $versionInfo = sprintf "%d", q$Revision: 9 $ =~ /: (\d+)/;
# If thing will be done differently this has to change!
my $tarTypeVersion = 1;
# Set stuff for GETOPT
my ($dcm_source, $targetlocation);
my $verbose    = 0;
my $profile    = undef;
my $neurodbCenterName = undef;
my $clobber    = 0;
my $dbase      = 0;
my $todayDate  = 0;
my $mri_upload_update =0;
my $Usage = "------------------------------------------


  Author    :        J-Sebastian Muehlboeck
  Date      :        2006/10/01
  Version   :        $versionInfo


WHAT THIS IS:

A tool for archiving DICOM data. Point it to a source directory and provide a
target directory which will be the archive location.
- If the source contains only one valid STUDY worth of DICOM it will create a
  descriptive summary, a (gzipped) DICOM tarball.
  The tarball with the metadata and a logfile will then be retarred into the
  final TARCHIVE.
- md5sums are reported for every step.
- It can also be used with a MySQL database.


Documentation: perldoc dicomTar.pl


Usage:\n\t $0 </PATH/TO/SOURCE/DICOM> </PATH/TO/TARGET/DIR> [options]
\n\n See $0 -help for more info\n\n";

my @arg_table =
    (
     ["Input and database options", "section"],
     ["-today", "boolean", 1,     \$todayDate, "Use today's date for archive
     name instead of using acquisition date."],
     ["-database", "boolean", 1,  \$dbase, "Use a database if you have one set
     up for you. Just trying will fail miserably"],
     ["-mri_upload_update", "boolean", 1,  \$mri_upload_update, "update the
     mri_upload table by inserting the correct tarchiveID"],
     ["-clobber", "boolean", 1,   \$clobber, "Use this option only if you want
     to replace the resulting tarball!"],
     ["-profile","string",1, \$profile, "Specify the name of the config file
     which resides in .loris_mri in the current directory."],
     ["-centerName","string",1, \$neurodbCenterName, "Specify the symbolic
     center name to be stored alongside the DICOM institution."],
     ["General options", "section"],
     ["-verbose", "boolean", 1,   \$verbose, "Be verbose."],
     ["-version", "boolean", 1,   \$version, "Print cvs version number and
     exit."],
     );

GetOptions(\@arg_table, \@ARGV) ||  exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

if ($version) { print "Version: $versionInfo\n"; exit; }

# checking for profile settings
if ( !$profile ) {
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
if(-f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
	{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
}
if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}
# The source and the target dir have to be present and must be directories.
# The absolute path will be supplied if necessary
if(scalar(@ARGV) != 2) {
    print STDERR $Usage . "\n\tERROR: Missing source and/or target\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
$dcm_source     = abs_path($ARGV[0]);
$targetlocation = abs_path($ARGV[1]);
#if (!$dcm_source || !$targetlocation) { print $Usage; exit 1; }
if (-d $dcm_source && -d $targetlocation) {
    $dcm_source =~ s/^(.*)\/$/$1/;
    $targetlocation =~ s/^(.*)\/$/$1/;
} else {
    print STDERR "\nERROR: source and target must be existing directories!\n\n";
    exit $NeuroDB::ExitCodes::INVALID_PATH;
}

# The tar target 
my $totar = basename($dcm_source);
print "Source: ". $dcm_source . "\nTarget: ".  $targetlocation . "\n\n"
    if $verbose;
my $ARCHIVEmd5sum = 'Provided in database only';


# establish database connection if database option is set
my $dbh;
if ($dbase) {
    $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
    print "Testing for database connectivity.\n" if $verbose;
    $dbh->disconnect();
    print "Database is available.\n\n" if $verbose;
}

# ***************************************    main    *************************************** 
#### get some info about who created the archive and where and when
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my $date            = sprintf("%4d-%02d-%02d %02d:%02d:%02d\n",
                    $year+1900,$mon+1,$mday,$hour,$min,$sec);
my $today           = sprintf("%4d-%02d-%02d",$year+1900,$mon+1,$mday);
my $hostname        = inet_ntoa(scalar(gethostbyname(hostname() || 'localhost')));
                    #`hostname -f`;
                    # # fixme specify -f for fully qualified if you need it.
my $system          = `uname`;


# Remove all files starting with . in the dcm_source directory
my $cmd = "cd " . $dcm_source . "; find -type f -name '.*' | xargs rm -f";
system($cmd);
# Remove __MACOSX directory
my $cmd = "cd " . $dcm_source . "; find -name '__MACOSX' | xargs rm -rf";
system($cmd);

# create new summary object
my $summary = DICOM::DCMSUM->new($dcm_source,$targetlocation);
# determine the name for the summary file
my $metaname = $summary->{'metaname'};
# get the summary type version
my $sumTypeVersion = $summary->{'sumTypeVersion'};
# get the unique study ID
my $studyUnique = $summary->{'studyuid'};
my $creator         = $summary->{user};
my $sumTypeVersion  = $summary->{sumTypeVersion}; 

# check if the study is already uploaded in the tarchive tables
if ($dbase) {
    $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
    my ($unique_study, $message) = $summary->is_study_unique($dbh, $clobber, undef);
    # if there is a message returned, it means the script should stop running
    # and display the error message as the study is not unique
    if (!$unique_study && !$clobber) {
        print STDERR $message;
        exit $NeuroDB::ExitCodes::FILE_NOT_UNIQUE;
    }
    $dbh->disconnect();
}

my $byDate;
# Determine how to name the archive... by acquisition date or by today's date.
if ($todayDate) {
    $byDate = $today;
} else {
    $byDate = $summary->{header}->{scandate};
} # wrap up the archive
my $finalTarget = "$targetlocation/DCM_${byDate}_$summary->{metaname}.tar";

if (-e $finalTarget && !$clobber) {
    print STDERR "\nTarget exists. Use clobber to overwrite!\n\n";
    exit $NeuroDB::ExitCodes::TARGET_EXISTS_NO_CLOBBER;
}

# read acquisition metadata into variable 
my $metafile = "$targetlocation/$metaname.meta";
open META, ">$metafile";
META->autoflush(1);
select(META);
$summary->dcmsummary();
my $metacontent = $summary->read_file("$metafile");

# write to STDOUT again
select(STDOUT);

# get rid of newline
chomp($hostname,$system);

#### create tar from rigt above the source 
chdir(dirname($dcm_source));
print "You will archive the dir\t\t: $totar\n" if $verbose;
# tar contents into tarball
my $command = "tar -cf $targetlocation/$totar.tar $totar\n";
print "\nYou are creating a tar with the following command:
        \n$command\n" if $verbose;
`$command`;

# chdir to targetlocation create md5sums gzip and wrap the whole thing up again
# into a retarred archive
chdir($targetlocation);
print "\ngetting md5sums and gzipping!!\n" if $verbose;
my $DICOMmd5sum = DICOM::DCMSUM::md5sum($totar.".tar"); #`md5sum $totar.tar`;
`gzip -nf $totar.tar`;
my $zipsum =  DICOM::DCMSUM::md5sum($totar.".tar.gz");

# create tar info for the tarball NOT  containing md5 for archive tarball
open TARINFO, ">$totar.log";
select(TARINFO);
&archive_head;
close TARINFO;
select(STDOUT);
my $tarinfo = &read_file("$totar.log"); 

my $retar = "tar cvf DCM\_$byDate\_$totar.tar $totar.meta $totar.log $totar.tar.gz";
`$retar`;
$ARCHIVEmd5sum =  DICOM::DCMSUM::md5sum("DCM\_$byDate\_$totar.tar");

# create tar info for database containing md5 for archive tarball
open TARINFO, ">$totar.log";
select(TARINFO);
&archive_head;
close TARINFO;
select(STDOUT);
$tarinfo = &read_file("$totar.log"); 
print  $tarinfo if $verbose;


# if -dbase has been given create an entry based on unique studyID
# Create database entry checking for already existing entries...
my $success;
if ($dbase) {
    $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
    print "\nAdding archive info into database\n" if $verbose;
    my $update          = 1 if $clobber;
    my $ArchiveLocation = $finalTarget;
    $ArchiveLocation    =~ s/$targetlocation\/?//g;
    $success            = $summary->database($dbh, $metaname, $update,
                            $tarTypeVersion, $tarinfo, $DICOMmd5sum,
                            $ARCHIVEmd5sum, $ArchiveLocation,
                            $neurodbCenterName);
}

# delete tmp files
print "\nRemoving temporary files from target location\n\n" if $verbose;
`rm -f $totar.tar.gz $totar.meta $totar.log`;

# now report database failure (was not above to ensure temp files were erased)
if ($dbase) {
    if ($success) {
        print "\nDone adding archive info into database\n" if $verbose;
    } else {
        print STDERR "\nThe database command failed\n";
        exit $NeuroDB::ExitCodes::INSERT_FAILURE;
    }
}

# call the updateMRI_upload script###
if ($mri_upload_update) {
    my $script =  "updateMRI_Upload.pl"
                 . " -profile $profile -globLocation -tarchivePath $finalTarget"
                 . " -sourceLocation $dcm_source";
    my $output = system($script);
    if ($output!=0)  {
        print STDERR "\n\tERROR: the script updateMRI_Upload.pl has failed\n\n";
        exit $NeuroDB::ExitCodes::UPDATE_FAILURE;
    }
}


exit $NeuroDB::ExitCodes::SUCCESS;

=pod 

=head3 archive_head()

Function that prints the DICOM archive header

=cut

sub archive_head {
    $~ = 'FORMAT_HEADER';
    write();
}

format FORMAT_HEADER =

* Taken from dir                   :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $dcm_source,
* Archive target location          :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $finalTarget,
* Name of creating host            :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $hostname,                                
* Name of host OS                  :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $system,
* Created by user                  :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $creator,                                
* Archived on                      :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $date,
* dicomSummary version             :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $sumTypeVersion,
* dicomTar version                 :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $tarTypeVersion,
* md5sum for DICOM tarball         :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $DICOMmd5sum,
* md5sum for DICOM tarball gzipped :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $zipsum,
* md5sum for complete archive      :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      $ARCHIVEmd5sum,
.

=pod 

=head3 read_file($file)

Function that reads file contents into a variable

INPUT: file to be read

RETURNS: file contents

=cut

sub read_file {
    my $file = shift;
    my $content;
    open CONTENT, "$file";
    while ( <CONTENT> ) {
	$content = $content . $_;
    }
    close CONTENT;
    return $content;
}


__END__

=pod

=head1 TO DO

Fix comments written as #fixme in the code.

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

J-Sebastian Muehlboeck,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

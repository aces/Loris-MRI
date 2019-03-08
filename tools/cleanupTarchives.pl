#! /usr/bin/perl

=pod

=head1 NAME

cleanupTarchives.pl -- script to clean up duplicated DICOM archives in the filesystem

=head1 SYNOPSIS

perl cleanupTarchives.pl C<[options]>

Available options are:

-profile: name of the config file in C<../dicom-archive/.loris-mri>

=head1 DESCRIPTION

The program greps the list of C<ArchiveLocation>/C<md5sumArchive> from the
C<tarchive> table of the database and compares it to the list of DICOM archive
files present in the filesystem. If more than one file is found on the
filesystem for a given database entry, it will compare the C<md5sum> and the archive
location and remove the duplicate DICOM archives that do not match both the C<md5sum>
and the archive location.

=head2 Methods

=cut


##############################
####    Use statements    ####
##############################
use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;

## NeuroDB modules
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::ExitCodes;








##############################
####   Initiate program   ####
##############################
my $profile;
my $profile_desc = "name of config file in ../dicom-archive/.loris_mri";

my @opt_table =  (
    [ "-profile", "string", 1, \$profile, $profile_desc ]
);

#TODO set up the help section
my $Help = <<HELP;
The program greps the list of C<ArchiveLocation>/C<md5sumArchive> from the
C<tarchive> table of the database and compares it to the list of DICOM archive
files present in the filesystem. If more than one file is found on the
filesystem for a given database entry, it will compare the md5sum and the archive
location and remove the duplicate DICOM archives that do not match both the md5sum
and the archive location only.
HELP

my $Usage = <<USAGE;
usage: $0 [options]
       $0 -help to list options
USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

# input option error checking
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




##############################
##  Establish db connection ##
##############################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

##############################
####  Initiate variables  ####
##############################
# These settings are in the database, accessible from the Configuration module
my $data_dir           = &NeuroDB::DBI::getConfigSetting(\$dbh,'dataDirBasepath'   );
my $tarchiveLibraryDir = &NeuroDB::DBI::getConfigSetting(\$dbh,'tarchiveLibraryDir');
$tarchiveLibraryDir    =~ s/\/$//g;


##############################
####      Create Log      ####
##############################
# create logdir(if !exists) and logfile
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $date = sprintf(
    "%4d-%02d-%02d %02d:%02d:%02d",
    $year+1900, $mon+1, $mday, $hour, $min, $sec
);
my $LogDir = "$data_dir/logs";
mkdir ($LogDir, 0770) if (!-d $LogDir);
my $logfile = "$LogDir/RemoveDuplicateTarchives_$date.log";
open LOG, ">$logfile";
LOG->autoflush(1);

print LOG "\n==> Successfully connected to database \n";

##############################
####     Main program     ####
##############################

# Gets the list of DICOM archives from the tarchive table of the database and stores
# the ArchiveLocation and md5sumArchive fields in a hash where ArchiveLocation will
# be the key of the hash and md5sumArchive will be the value of the hash.
my ($tarchivesList_db) = &selectTarchives($dbh, $tarchiveLibraryDir);

# Loop through the list of DICOM archives in the year subfolders
foreach my $tarchive_db (keys %$tarchivesList_db) {

    # Get tarchive basename
    my ($tarBasename_db) = &getTarchiveBasename($tarchive_db);

    # Get the list of tarchives in the tarchive library folder that matches 
    # the basename of the tarchive stored in the year subfolder.
    my ($tarFileList) = &getTarList($tarchiveLibraryDir, $tarBasename_db);

    # Next if did not find any duplicate tarchives in tarchive library folder
    if (@$tarFileList <= 0) {
        print LOG "WARNING: no DICOM archive found in the file system corresponding "
                  . "to the database entry $tarchive_db\n";
        next;
    }
    
    # Identify duplicate DICOM archives in the file system and remove them
    my ($duplicateTarFiles, $realTarFileFound)  = &identifyDuplicates(
        $tarchive_db, $tarchivesList_db, $tarFileList
    );
    if (($realTarFileFound) && (@$duplicateTarFiles > 0)) {
        &removeDuplicates($duplicateTarFiles);
    }
}

exit $NeuroDB::ExitCodes::SUCCESS;



##############################
####       Functions      ####
##############################

=pod

=head3 readTarDir($tarDir, $match)

Read the C<tarchive> library folder and return the list of files matching the regex
stored in C<$match>.

INPUTS:
  - $tarDir: C<tarchive> library directory (in which DICOM archives are stored)
  - $match : regular expression to use when parsing the DICOM archive library folder

RETURNS: the list of matching DICOM archives into a dereferenced array

=cut

sub readTarDir {
    my ($tarDir, $match) = @_;

    # Read tarchive directory 
    opendir (DIR, "$tarDir") || die "Cannot open $tarDir\n";
    my @entries = readdir(DIR);
    closedir (DIR);

    ## Keep only files that match string stored in $match
    my @tar_list = grep(/^$match/i, @entries);
    @tar_list    = map  {"$tarDir/" . $_} @tar_list;
    
    return (\@tar_list);
}











=pod

=head3 getTarList($tarchiveLibraryDir, $match)

Read the year sub-folders in the DICOM archive library folder and return the list of
files matching the regex stored in C<$match>.

INPUTS:
  - $tarDir     : C<tarchive> library directory (in which DICOM archives are stored)
  - $YearDirList: array containing the list of year sub-folders
  - $match      : regular expression to use when parsing the C<tarchive> library
                  folder

RETURNS: the list of matching DICOM archives into a dereferenced array

=cut

sub getTarList {
    my ($tarchiveLibraryDir, $match)  = @_;

    my ($tar_list)    = readTarDir($tarchiveLibraryDir, $match    );
    my ($YearDirList) = readTarDir($tarchiveLibraryDir, '\d\d\d\d');

    foreach my $YearDir (@$YearDirList) {

        my ($yearList) = readTarDir("$YearDir", $match);
        ## Add year subfolder in front of each element (file) of the array 

        ## Push the list of tarchives in the year subfolder to the overall list of tarchives
        push (@$tar_list, @$yearList) if (@$yearList >= 0);
    
    }    

    return ($tar_list);
}





=pod

=head3 selectTarchives($dbh, $tarchiveLibraryDir)

Function that will select the C<ArchiveLocation> and C<md5sumArchive> fields of the
tarchive table for all entries stored in that table.

INPUTS:
  - $dbh               : the database handle object
  - $tarchiveLibraryDir: tarchive library directory (e.g. /data/project/data/tarchive)

RETURNS:
    - \%tarchiveInfo: hash of the DICOM archives found in the database, with the
                      C<ArchiveLocation> as keys and C<md5sum> information as values

=cut

sub selectTarchives {
    my ($dbh, $tarchiveLibraryDir) = @_;

    my $query = "SELECT ArchiveLocation, md5sumArchive FROM tarchive";
    my $sth   = $dbh->prepare($query);
    $sth->execute();

    my %tarchiveInfo;
    if ($sth->rows > 0) {
        while (my $row = $sth->fetchrow_hashref) {
            my $tarchive = $tarchiveLibraryDir . "/" . $row->{'ArchiveLocation'};
            $tarchiveInfo{$tarchive} = $row->{'md5sumArchive'};
        }
    } else {
        print LOG "\nERROR: no archived data found in the tarchive table.\n\n";
        exit $NeuroDB::ExitCodes::SELECT_FAILURE;
    }

    return (\%tarchiveInfo); 
}





=pod

=head3 getTarchiveBasename($tarchive)

Function that will determine the DICOM archive basename from the C<ArchiveLocation>
stored in the database. It will, among other things, get rid of the C<_digit part>
that was inserted in the past by the C<tarchiveLoader>.

INPUT: C<ArchiveLocation> that was stored in the C<tarchive> table of the database.

RETURNS: the DICOM archive basename to use when looking for duplicate DICOM archives
         in the C<tarchive> library directory of the filesystem

=cut

sub getTarchiveBasename {
    my ($tarchive)  = @_;

    my $tarBasename = substr(basename($tarchive), 0, -4);

    ## remove the _\d of the name of the tarchive
    if ($tarBasename =~ m/_\d$/) {
        $tarBasename =~ s/_\d$//i;
    }

    return ($tarBasename);
}




=pod

=head3 identifyDuplicates($tarchive_db, $tarchivesList_db, $tarFileList)

Function that will identify the duplicate DICOM archives present in the filesystem.

INPUTS:
  - $tarchive_db     : DICOM archive file stored in the database's C<tarchive> table
  - $tarchivesList_db: hash with the list of DICOM archives locations stored in the
                       database (keys of the hash) and their corresponding md5sum
                       (values of the hash)
  - tarFileList      : list of DICOM archives found in the filesystem that match
                       the basename of C<$tarchive_db>

RETURNS:
  - Undef: if did not find any DICOM archive on the filesystem matching the file
           stored in the database
  - @duplicateTarFiles: list of duplicate DICOM archive found in the filesystem
  - $realTarFileFound : path to the actual DICOM archive that matches the one in
                        the C<tarchive> table of the database

=cut

sub identifyDuplicates {
    my ($tarchive_db, $tarchivesList_db, $tarFileList)  = @_;

    # Get md5 information for the DICOM archive stored in the database
    my ($md5_db, $tar_db) = split (' ', $tarchivesList_db->{$tarchive_db});

    # Loop through the DICOM archive files found in the file system and determine
    ## which one is the one stored in the database
    my $realTarFileFound = undef;
    my @duplicateTarFiles;
    foreach my $tarFile (@$tarFileList) {
        # Get md5 information for the file found in the filesystem
        my $md5_check           = `md5sum $tarFile`;
        my ($md5_file, $file)   = split (' ', $md5_check);

        # Compare the database's md5 with the tarchive found in the filesystem's md5
        if (($md5_file eq $md5_db) && ($tarFile eq $tarchive_db)) {
            print "File match $tarchive_db\n$tarFile\n";
            $realTarFileFound   = $tarFile;
        } else {
            print "Duplicate file?... \n $tarchive_db\n$tarFile\n";
            push (@duplicateTarFiles, $tarFile);
        }
    }

    # If no real tarchive file found return undef, 
    ## else return table with list of duplicates and real file found
    if (!$realTarFileFound) {
        print LOG "No tarchive file matching $tarchive_db was found in the filesystem\n";
        return undef;
    } else {
        print LOG "Duplicate tarchive(s) found for $tarchive_db.\n"; 
        return (\@duplicateTarFiles, $realTarFileFound);
    }
}    



=pod

=head3 removeDuplicates($duplicateTars)

Function that removes the duplicate DICOM archives stored in dereferenced
array C<$duplicateTars> from the filesystem.

INPUT: list of the duplicate DICOM archives found on the filesystem

=cut

sub removeDuplicates {
    my ($duplicateTars) = @_;

    foreach my $tarFile (@$duplicateTars) {
        print LOG "Removing duplicate $tarFile\n";
        my ($cmd) = "rm $tarFile";
        system ($cmd);
    }
}


=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut

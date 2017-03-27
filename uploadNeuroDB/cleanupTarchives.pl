#! /usr/bin/perl

=pod

=cut


##############################
####    Use statements    ####
##############################
use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use FindBin;

## NeuroDB modules
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;








##############################
####   Initiate program   ####
##############################
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)    = localtime(time);
my $date    = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $profile = undef;

my @opt_table   =  (
                    ["-profile     ","string",1, \$profile, "name of config file in ../dicom-archive/.loris_mri"]
                   );

my $Help        = <<HELP;
blablabla
HELP

my $Usage = <<USAGE;
usage: $0 </path/to/DICOM-tarchive> [options]
$0 -help to list options
USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;

# input option error checking
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ($profile && !defined @Settings::db) { 
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; 
    exit 33; 
}



##############################
##  Establish db connection ##
##############################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";

##############################
####  Initiate variables  ####
##############################
# These settings are in the database, accessible from the Configuration module
my $data_dir = &NeuroDB::DBI::getConfigSetting(
                    $this->{dbhr},'dataDirBasepath'
                    );
my $tarchiveLibraryDir = &NeuroDB::DBI::getConfigSetting(
                       $this->{dbhr},'tarchiveLibraryDir'
                       );
$tarchiveLibraryDir     =~ s/\/$//g;


##############################
####      Create Log      ####
##############################
# create logdir(if !exists) and logfile
my $LogDir   = "$data_dir/logs"; 
mkdir ($LogDir, 0770) if (!-d $LogDir);
my $logfile  = "$LogDir/RemoveDuplicateTarchives_$date.log";
open LOG, ">$logfile";
LOG->autoflush(1);

##############################
####     Main program     ####
##############################

# Get tarchives list from the database and stores ArchiveLocation and md5sumArchive informations in a hash.
## ArchiveLocation will be the key of the hash
## md5sumArchive will be the value of the hash
my ($tarchivesList_db)  = &selectTarchives($dbh, $tarchiveLibraryDir);

# Loop through the list of tarchives in the year subfolders
foreach my $tarchive_db (keys %$tarchivesList_db) {

    # Get tarchive basename
    my ($tarBasename_db)    = &getTarchiveBasename($tarchive_db);

    # Get the list of tarchives in the tarchive library folder that matches 
    # the basename of the tarchive stored in the year subfolder.
    my ($tarFileList)       = &getTarList($tarchiveLibraryDir, $tarBasename_db);
    # Next if did not find any duplicate tarchives in tarchive library folder
    if (@$tarFileList <= 0) {
        print LOG "WARNING: no tarchive was found in the file system that matches $tarchive_db\n";
        next;
    }
    
    # Identify duplicate tarchives in the file system and remove them 
    my ($duplicateTarFiles, $realTarFileFound)  = &identifyDuplicates($tarchive_db, $tarchivesList_db, $tarFileList);
    if (($realTarFileFound) && (@$duplicateTarFiles > 0)) {
        &removeDuplicates($duplicateTarFiles);
    }
}

exit 0;



##############################
####       Functions      ####
##############################

=pod
Read the tarchive library folder and return the list of files matching the regex stored in $match.
Inputs: - $tarDir   = tarchive library directory (in which tarchives are stored)
        - $match    = regular expression to use when parsing the tarchive library folder
Outputs:- @tar_list = return the list of matching tarchives into a dereferenced array
=cut
sub readTarDir {
    my ($tarDir, $match) = @_;

    # Read tarchive directory 
    opendir (DIR, "$tarDir") || die "Cannot open $tarDir\n";
    my @entries = readdir(DIR);
    closedir (DIR);

    ## Keep only files that match string stored in $match
    my @tar_list    = grep(/^$match/i, @entries);
    @tar_list       = map  {"$tarDir/" . $_} @tar_list; 
    
    return (\@tar_list);
}











=pod
Read the year subfolder in the tarchive library folder and return the list of files matching the regex stored in $match.
Inputs: - $tarDir       = tarchive library directory (in which tarchives are stored)
        - $YearDirList  = array containing the list of year subfolders
        - $match        = regular expression to use when parsing the tarchive library folder
Outputs:- @tar_list     = return the list of matching tarchives into a dereferenced array
=cut
sub getTarList {
    my ($tarchiveLibraryDir, $match)  = @_;

    my ($tar_list)      = readTarDir($tarchiveLibraryDir, $match);


    my ($YearDirList)   = readTarDir($tarchiveLibraryDir, '\d\d\d\d');

    foreach my $YearDir (@$YearDirList) {

        my ($yearList)  = readTarDir("$YearDir", $match);
        ## Add year subfolder in front of each element (file) of the array 

        ## Push the list of tarchives in the year subfolder to the overall list of tarchives
        push (@$tar_list, @$yearList) if (@$yearList >= 0);
    
    }    

    return ($tar_list);
}





=pod
Function that will select the ArchiveLocation and md5sumArchive fields of the tarchive table for all entries stored in that tarchive table. 
Input:  - $dbh           = the database handle object
Output: - \%tarchiveInfo = hash of the tarchives found in the database, with the ArchiveLocation as keys and md5sum information as values
=cut
sub selectTarchives {
    my ($dbh, $tarchiveLibraryDir)   = @_;

    my $query   = "SELECT ArchiveLocation, md5sumArchive FROM tarchive";

    my $sth     = $dbh->prepare($query);
    $sth->execute();

    my %tarchiveInfo;
    if ($sth->rows > 0) {
        while (my $row = $sth->fetchrow_hashref) {
            my $tarchive = $tarchiveLibraryDir . "/" . $row->{'ArchiveLocation'};
            $tarchiveInfo{$tarchiveLibraryDir}  = $row->{'md5sumArchive'};
        }
    } else {
        print LOG "\n ERROR: no archived data found in tarchive table.\n\n";
        exit 0;
    }

    return (\%tarchiveInfo); 
}





=pod
Function that will determine the tarchive basename from the ArchiveLocation stored in the database. 
It will, among other things, get rid of the _digit part that was inserted in the past by the tarchiveLoader.
Input: - $tarchive      = ArchiveLocation that was stored in the tarchive table of the database.
Output:- $tarBasename   = tarchive basename to use to look for duplicate tarchive in the tarchive library directory of the filesystem
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
Function that will identify the duplicate tarchives present in the filesystem.
- Inputs: - $tarchive_db      = tarchive file stored in the tarchive table of the database
          - $tarchivesList_db = hash with the list of tarchives stored in the database (keys of the hsh) and their corresponding md5sum (values of the hash) 
          - tarFileList       = list of tarchives found in the filesystem that matches the basename of $tarchive_db
- Outputs: - Undef => if no tarchive matching the file stored in the database could be found in the filesystem.
           - @duplicateTarFiles and $realTarFileFound => if the file stored in the database matches one file of the tarFileList present in the filesystem. 
=cut
sub identifyDuplicates {
    my ($tarchive_db, $tarchivesList_db, $tarFileList)  = @_;

    # Get md5 information for the Archive stored in the db
    my ($md5_db, $tar_db) = split (' ', $tarchivesList_db->{$tarchive_db});

    # Loop through the tarchive files found in the file system and determine 
    ## which one is the one stored in the DB    
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
Function that removes the duplicate tarchives stored in dereferenced array $duplicateTars from the filesystem.
Input: - $duplicateTars = list of the duplicate tarchives found on the filesystem 
=cut
sub removeDuplicates {
    my ($duplicateTars) = @_;

    foreach my $tarFile (@$duplicateTars) {
        print LOG "Removing duplicate $tarFile\n";
        my ($cmd)   = "rm $tarFile";
        system ($cmd);
    }
}   

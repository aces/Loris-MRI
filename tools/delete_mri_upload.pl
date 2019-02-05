#!/usr/bin/perl

=pod

=head1 NAME

delete_mri_upload.pl -- Delete eveything that was produced by the MRI pipeline for a given MRI upload

=head1 SYNOPSIS

perl delete_mri_upload.pl [-profile file] [-i] [-n]

Available options are:

-profile     : name of the config file in C<../dicom-archive/.loris_mri> (defaults to C<prod>).

-i           : when performing the file backup, ignore files that do not exist or are not readable
               (default is to abort if such a file is found). This option is ignored if C<-n> is used.
               
-n           : do not backup the files produced by the MRI pipeline for this upload (default is to
               perform a backup).


=head1 DESCRIPTION

This program deletes all the files and database records produced by the MRI pipeline for a given 
MRI upload. More specifically, the script will remove the records associated to the MRI upload whose
ID is passed on the command line from the following tables: C<notification_spool>, C<tarchive_series>
C<tarchive_files>, C<files_intermediary>, C<parameter_file>, C<files>, C<mri_violated_scans>
C<mri_violations_log>, C<MRICandidateErrors>, C<mri_upload> and C<tarchive>. It will also delete from 
the file system the files that are associated to the upload and are listed in tables C<files>
C<files_intermediary> and C<parameter_file>. The script will abort and will not delete anything if there 
is QC information associated to the upload (i.e entries in tables C<files_qcstatus> or C<feedback_mri_comments>).
If the script finds a file that is listed in the database but that does not exist on the file system or is not
readable, the script will issue an error message and abort, leaving the file system and database untouched. 
This behaviour can be changed with option C<-i>. By default, the script will create a backup of all the files 
that it plans to delete before actually deleting them. Use option C<-n> to perform a 'hard' delete (i.e. no backup).
The backup file name will be C<mri_upload.<UPLOAD_ID>.tar.gz>. Note that the file paths inside this backup archive
are absolute.

=head2 Methods

=cut

use strict;
use warnings;

use NeuroDB::DBI;
use NeuroDB::ExitCodes;
use NeuroDB::MRI;

use Getopt::Tabular;       

use File::Temp qw/tempfile/;

use constant DEFAULT_PROFILE           => 'prod';
use constant DEFAULT_DIE_ON_FILE_ERROR => 1;
use constant DEFAULT_NO_BACKUP         => 0;

use constant PIC_SUBDIR                => 'pic';

my $profile        = DEFAULT_PROFILE;
my $dieOnFileError = DEFAULT_DIE_ON_FILE_ERROR;
my $noBackup       = DEFAULT_NO_BACKUP;


my @opt_table = (
    ['-profile', 'string' , 1, \$profile, 
     'name of config file in ../dicom-archive/.loris_mri (defaults to "prod")'],
    ['-i'     , 'const'   , 0, \$dieOnFileError, 
     'When performing the file backup, ignore files that do not exist or are not readable.'
     . ' Default is to abort if such a file is found.'],
    ['-n'     , 'const'   , 0, \$noBackup,
     'Do not backup anything. Default is to backup all files to be deleted '
     . 'into an archive named "mri_upload.<uploadID>.tar.gz", in the '
     . 'current directory']
);

my $Help = <<HELP;
HELP

my $usage = <<USAGE;
Usage: $0 [-profile profile] [-i] [-n] uploadID
USAGE

&Getopt::Tabular::SetHelp($Help, $usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

if(@ARGV != 1) {
	print "$usage";
	exit $NeuroDB::ExitCodes::MISSING_ARG;
}

my $uploadID = $ARGV[0];

#======================================#
# Validate all command line arguments  #
#======================================#
if (!$ENV{LORIS_CONFIG}) {
	print STDERR "\n\tERROR: Environment variable 'LORIS_CONFIG' not set\n\n";
	exit $NeuroDB::ExitCodes::INVALID_ENVIRONMENT_VAR; 
}

if (!-e "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
    print $Help; 
    print STDERR "Cannot read profile file '$ENV{LORIS_CONFIG}/.loris_mri/$profile'\n";  
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

# Incorporate contents of profile file
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }

if ( !@Settings::db ) {
    print STDERR "ERROR: You don't have a \@db setting in file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}

#==================================#
# Establish database connection    #
#==================================#
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

my $dataDirBasepath    = NeuroDB::DBI::getConfigSetting(\$dbh,'dataDirBasepath');
$dataDirBasepath =~ s!/$!!;
my $tarchiveLibraryDir = NeuroDB::DBI::getConfigSetting(\$dbh,'tarchiveLibraryDir');
$tarchiveLibraryDir =~ s!/$!!;

my $query = "SELECT m.TarchiveID, t.ArchiveLocation, m.SessionID "
    .       "FROM mri_upload m "
    .       "JOIN tarchive t USING (TarchiveID) "
    .       "WHERE m.UploadID = ?";
my $sth = $dbh->prepare($query);
$sth->execute($uploadID);
my($tarchiveID, $archiveLocation, $sessionID) = $sth->fetchrow_array();

if($sth->rows == 0) {
	print STDERR "No upload found in table mri_upload with upload ID '$uploadID'\n";
	exit $NeuroDB::ExitCodes::INVALID_ARG;
}

if(!$tarchiveID) {
	print STDERR "No tarchive ID found in table mri_upload for upload with ID $uploadID\n";
	exit $NeuroDB::ExitCodes::INVALID_ARG;
}

if(!defined $tarchiveLibraryDir && $archiveLocation !~ /^\//) {
    print STDERR "Cannot determine absolute path for archive '$archiveLocation' "
        . "since config setting 'tarchiveLibraryDir' is not set. Aborting.\n";
    exit $NeuroDB::ExitCodes::MISSING_CONFIG_SETTING;
}

$archiveLocation = "$tarchiveLibraryDir/$archiveLocation" unless $archiveLocation =~ /^\//;

#===================================================#
# Make sure there are no entries in files_qc_status #
# and feedback_mri_comments for the files in the    #
# archive                                           #
#===================================================#

if(&hasQcOrComment($dbh, $uploadID, $tarchiveID)) {
	print STDERR "Cannot delete upload '$uploadID': there is QC information"
        . " associated to that archive\n";
	exit $NeuroDB::ExitCodes::INVALID_ARG;
}

#===========================================#
# Backup all files found in                 #
# tables files and files_intermediary for   #
# the specified upload_id                   #
#===========================================#

my $filesRef             = &getFilesRef($dbh, $tarchiveID, $dataDirBasepath);
my $intermediaryFilesRef = &getIntermediaryFilesRef($dbh, $tarchiveID, $dataDirBasepath);
my $picFilesRef          = &getPicFilesRef($dbh, $tarchiveID, $dataDirBasepath);

unless($noBackup) {
    &backupFiles($uploadID, $archiveLocation, $filesRef, $intermediaryFilesRef, $picFilesRef);
}
&deleteUploadInDatabase($dbh, $uploadID, $tarchiveID, $sessionID, $intermediaryFilesRef, $picFilesRef);
&deleteUploadFiles($archiveLocation, $filesRef, $intermediaryFilesRef, $picFilesRef);

print "Upload $uploadID successfully deleted.\n";
exit $NeuroDB::ExitCodes::SUCCESS;

=pod

=head3 hasQcOrComment($dbh, $tarchiveID)

Determines if a tarchive has QC information associated to it by looking at the
contents of tables C<files_qcstatus> and C<feedback_mri_comments>.

INPUTS:

  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the tarchive.

RETURNS:

  1 if there is QC information associated to the archive, 0 otherwise.

=cut
sub hasQcOrComment {
	my($dbh, $tarchiveID) = @_;
	
	#=========================================#
    # Fetch contents of tables files_qcstatus #
    # and feedback_mri_comments               #
    #=========================================#
    (my $query =<<QUERY) =~ s/\s+/ /g;
         SELECT fqs.FileID
         FROM files_qcstatus fqs 
         JOIN files f USING (FileID)
         WHERE f.TarchiveSource = ?
         
         UNION
          
         SELECT fmc.FileID
         FROM feedback_mri_comments fmc 
         JOIN files f USING (FileID)
         WHERE f.TarchiveSource = ?
         LIMIT 1
QUERY

    my $rowsRef = $dbh->selectall_arrayref($query, undef, $tarchiveID, $tarchiveID);

	return @$rowsRef > 0;
}

=pod

=head3 getFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table C<files>.

INPUTS:

  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the tarchive.
  - $dataDirBasePath: base path of the directory where all the files in table C<files>
                      are located (i.e config value of setting 'dataDirBasePath').

RETURNS: 

 an array of hash references. Each has has two keys: 'FileID' => ID of a file in table C<files>
 and 'File' => absolute path of the file with the given ID.

=cut
sub getFilesRef {
	my($dbh, $tarchiveID, $dataDirBasePath) = @_;
	
	# Get FileID and File path of each files in files directly tied
	# to $tarchiveId
    $query = 'SELECT FileID, File FROM files WHERE TarchiveSource = ?';
    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

	# Make sure all paths are absolute paths
    foreach(@$filesRef) {
		$_->{'File'} = "$dataDirBasePath/$_->{'File'}" unless $_->{'File'} =~ /^\//;
	} 
	
	return $filesRef;   
}

=pod

=head3 getIntermediaryFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the intermediary files associated to an archive 
that are listed in table C<files_intermediary>.

INPUTS:

  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the tarchive.
  - $dataDirBasePath: base path of the directory where all the files in table C<files>
                      are located (i.e config value of setting 'dataDirBasePath').

RETURNS: 

  an array of hash references. Each hash has three keys: 'IntermedID' => ID of a file in 
  table C<files_intermediary> , 'FileID' => ID of this file in table C<files> and 
  'File' => absolute path of the file with the given ID.

=cut
sub getIntermediaryFilesRef {
	my($dbh, $tarchiveID, $dataDirBasePath) = @_;
	
	# This should get all files in table files_intermediary that are tied
	# indirectly to the tarchive with ID $tarchiveId
    my $query = 'SELECT fi.IntermedID, f.FileID, f.File FROM files_intermediary fi '
        .       'JOIN files f ON (fi.Output_FileID=f.FileID) '
        .       'WHERE f.SourceFileID IN (SELECT FileID FROM files WHERE TarchiveSource = ?)';

	my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

	# Make sure all paths are absolute paths
    foreach(@$filesRef) {
		$_->{'File'} = "$dataDirBasePath/$_->{'File'}" unless $_->{'File'} =~ /^\//;
	} 
	
	return $filesRef;   
}

=pod

=head3 getPicFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Gets the absolute paths of all the files associated to an archive 
that are listed in table C<parameter_file> and have a parameter
type set to C<check_pic_filename>.

INPUTS:

  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the tarchive.
  - $dataDirBasePath: base path of the directory where all the files in table C<files>
                      are located (i.e config value of setting 'dataDirBasePath').

RETURNS: 

  an array of hash references. Each hash has two keys: 'FileID' => FileID of a file 
  in table C<parameter_file> and 'Value' => absolute path of the file with the given ID.

=cut
sub getPicFilesRef {
	my($dbh, $tarchiveID, $dataDirBasePath) = @_;
	
	# Get all files in parameter_file with parameter_type set to
	# 'check_pic_filename' that are tied (indirectly) to the tarchive
	# with ID $tarchiveId
    (my $query =<<QUERY) =~ s/\s+/ /g;
        SELECT FileID, Value FROM parameter_file pf
	    JOIN files f USING (FileID)
        JOIN parameter_type AS pt
        ON (pt.ParameterTypeID=pf.ParameterTypeID)
        WHERE pt.Name='check_pic_filename'
	    AND (
	            f.TarchiveSource = ? 
	         OR f.SourceFileID IN (SELECT FileID FROM files WHERE TarchiveSource = ?)
	    )
QUERY

	my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID, $tarchiveID);
	
	# Make sure all paths are absolute paths
	foreach(@$filesRef) {
		if($_->{'Value'} !~ /^\//) {
		    $_->{'Value'} = sprintf("%s/%s/%s", $dataDirBasePath, PIC_SUBDIR, $_->{'Value'});
	    }
	}
	
	return $filesRef;
}

=pod

=head3 getBackupFileName

Gets the name of the tar compressed file that will contain a backup of all files
that the script will delete.


RETURNS: 

  backup file name.

=cut
sub getBackupFileName {
	my($uploadID) = @_;
	
	return "mri_upload.$uploadID.tar.gz";
}

=pod

=head3 backupFiles($uploadId, $archiveLocation, $filesRef, $intermediaryFilesRef, $picFilesRef)

Backs up all the files associated to the archive before deleting them. The backed up files will
be stored in a C<.tar.gz> archive where all paths are relative to C</> (i.e absolute paths).

INPUTS:

  - $uploadId  : ID of the upload to delete.
  - $archiveLocation: absolute path of the backed up archive created by the MRI pipeline.
  - $filesRef: reference to the array that contains all files in table C<files> associated to
               the upload.
  - $intermediaryFilesRef: reference to the array that contains all files in table C<files_intermediary>
                           associated to the upload.
  - $picFilesRef: reference to the array that contains all files in table C<parameter_file>
                  associated to the upload.
                  
=cut
sub backupFiles {
	my($uploadId, $archiveLocation, $filesRef, $intermediaryFilesRef, $picFilesRef) = @_;
	
	# Put in @files the absolutes paths of all files in tables files, intermediary_files
	# and parameter_files that are tied to the archive
	# Also put in @files the archive itself
	my @files = map { $_->{'File'} } @$filesRef;
	push(@files, map { $_->{'File'} } @$intermediaryFilesRef);
	push(@files, map { $_->{'Value'} } @$picFilesRef);
	push(@files, $archiveLocation);
	
	foreach my $f (@files) {
		# If file does not exist (i.e database and file system are not in sync)
		if(!-e $f) {
			if($dieOnFileError) {
				print STDERR "Cannot backup database files:\n";
				print STDERR "\tFile $f is in the database but was not found in $dataDirBasepath. Aborting.\n";
				exit $NeuroDB::ExitCodes::MISSING_FILES;
			}
			warn "Warning! File $f was not found in $dataDirBasepath (will not be backed up)\n";
		} elsif(!-r $f) {
			if($dieOnFileError) {
				print STDERR "Cannot backup database files:\n";
				print STDERR "\tFile $f is in database but is not readable. Aborting.\n";
				exit $NeuroDB::ExitCodes::UNREADABLE_FILE;
			}
			warn "Warning! File $f is not readable (will not be backed up)\n";
		}
	}
	
	# Create a temporary file that will list the absolute paths of all
	# files to backup (archive). 
    my($fh, $tmpFileName) = tempfile("$0.filelistXXXX", UNLINK => 1);
    foreach(@files) {
		print $fh "$_\n";
	}
	close($fh);
	
	# Put all files in a big compressed tar ball
    my $filesBackupPath = &getBackupFileName($uploadID);
    print "Backing up files related to upload $uploadID...\n";
	if(system('tar', 'zcvf', $filesBackupPath, '--absolute-names', '--files-from', $tmpFileName)) {
	    print STDERR "backup command failed: $!\n";
	    exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
    } 

	print "File $filesBackupPath successfully created.\n";
}

=pod

=head3 deleteUploadInDatabase($dbh, $uploadID, $tarchiveID, $sessionID, $intermediaryFilesRef, $picFilesRef)

This method deletes all information in the database associated to the given archive. More specifically, it 
deletes records from tables C<notification_spool>, C<tarchive_files>, C<tarchive_series>, C<files_intermediary>
C<parameter_file>, C<files>, C<mri_protocol_violated_scans>, C<mri_violations_log>, C<MRICandidateErrors>
C<mri_upload> and C<tarchive>. It will also set the CScan_done> value of the scan's session to 'N' if the upload
is the last upload tied to that session. All the delete/update operations are done inside a single transaction so 
either they all succeed or they all fail (and a rollback is performed).

INPUTS:
 
  - $dbh       : database handle.
  - $uploadId  : ID of the upload to delete.
  - $tarchiveID: ID of the tarchive to delete.
  - $sessionID : ID of the session associated to the scan,
  - $filesRef: reference to the array that contains all files in table C<files> associated to
               the upload.
  - $intermediaryFilesRef: reference to the array that contains all files in table C<files_intermediary>
                           associated to the upload.
  - $picFilesRef: reference to the array that contains all files in table C<parameter_file>
                  associated to the upload.
                  
=cut
sub deleteUploadInDatabase {
	my($dbh, $uploadID, $tarchiveID, $sessionID, $intermediaryFilesRef, $picFilesRef)= @_;
	
	$dbh->{'AutoCommit'} = 0;
	
	my $query = "DELETE FROM notification_spool WHERE ProcessID = ?";
	$dbh->do($query, undef, $uploadID);
	
	$query = "DELETE FROM tarchive_files WHERE TarchiveID = ?";
	$dbh->do($query, undef, $tarchiveID);
	
	$query = "DELETE FROM tarchive_series WHERE TarchiveID = ?";
	$dbh->do($query, undef, $tarchiveID);
	
	if(@$intermediaryFilesRef) {
		my @intermediaryFileIds = map { $_->{'IntermedID'} } @$intermediaryFilesRef;
		$query = sprintf(
		    'DELETE FROM files_intermediary WHERE IntermedID IN (%s)', 
		    join(',', map { '?' } (1..@intermediaryFileIds))
		);
		$dbh->do($query, undef, @intermediaryFileIds);
    }
    
 	if(@$picFilesRef) {
	    $query  = sprintf(
	        "DELETE FROM parameter_file WHERE FileID IN (%s)",
	        join(',', map { '?' } (1..@$picFilesRef))
	    );
	    $dbh->do($query, undef, map { $_->{'FileID'} } @$picFilesRef);
	}
	   	
	$query = sprintf(
	    "DELETE FROM files WHERE FileID IN (%s)",
	     join(',', map { '?' } (1..@$intermediaryFilesRef))
	);
	$dbh->do($query, undef, map { $_->{'FileID'} } @$intermediaryFilesRef);
	$query = "DELETE FROM files WHERE TarchiveSource = ?";
	$dbh->do($query, undef, $tarchiveID);
	
	$query = "DELETE FROM mri_protocol_violated_scans WHERE TarchiveID = ?";
	$dbh->do($query, undef, $tarchiveID);
	
	$query = "DELETE FROM mri_violations_log WHERE TarchiveID = ?";
	$dbh->do($query, undef, $tarchiveID);
	
	$query = "DELETE FROM MRICandidateErrors WHERE TarchiveID = ?";
	$dbh->do($query, undef, $tarchiveID);
	
	$query = "DELETE FROM mri_upload WHERE UploadID = ?";
	$dbh->do($query, undef, $uploadID);
	
	$query = "DELETE FROM tarchive WHERE TarchiveID = ?";
	$dbh->do($query, undef, $tarchiveID);
	
	# If the upload to delete is the last upload that was part of the 
	# session associated to it, then set the session's 'Scan_done' flag
	# to 'N'
	$query = "SELECT UploadID FROM mri_upload WHERE SessionID = ?";
	my $rowsRef = $dbh->selectall_arrayref($query, { Slice => {} }, $sessionID);
	if(@$rowsRef == 0) {
	    $query = "UPDATE session SET Scan_done = 'N' WHERE ID = ?";
	    $dbh->do($query, undef, $sessionID);
	}
	
	$dbh->commit;
    $dbh->{'AutoCommit'} = 0;
}

=pod

=head3 deleteUploadFiles($archiveLocation, $filesRef, $intermediaryFilesRef, $picFilesRef)

This method deletes form the file system all the files tied to the upload that were listed in
tables C<files>, C<files_intermediary> and <parameter_file>, along with the back up of the 
archive created by the MRI pipeline when the upload was processed. A warning is issued for any
file that could not be deleted.

INPUTS:
 
  - $archiveLocation: full path of the archive backup created by the MRI pipeline when the upload
                      was processed.
  - $filesRef: reference to the array that contains all files in table C<files> associated to
               the upload.
  - $intermediaryFilesRef: reference to the array that contains all files in table C<files_intermediary>
                           associated to the upload.
  - $picFilesRef: reference to the array that contains all files in table C<parameter_file>
                  associated to the upload.
                  
=cut
sub deleteUploadFiles {
	my($archiveLocation, $filesRef, $intermediaryFilesRef, $picFilesRef) = @_;
	
	# Delete all files. A warning will be issued for every file that could not be
	# deleted
	NeuroDB::MRI::deleteFiles( map { $_->{'File'} }  @$filesRef);
	NeuroDB::MRI::deleteFiles( map { $_->{'File'} }  @$intermediaryFilesRef);
	NeuroDB::MRI::deleteFiles( map { $_->{'Value'} } @$picFilesRef);
	
	# Delete the backed up archive
	NeuroDB::MRI::deleteFiles($archiveLocation);
}










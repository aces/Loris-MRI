#!/usr/bin/perl

=pod

=head1 NAME

delete_mri_upload.pl -- Delete everything that was produced by the imaging pipeline for a given set of imaging uploads

=head1 SYNOPSIS

perl delete_mri_upload.pl [-profile file] [-ignore] [-nobackup] [-uploadID lis_of_uploadIDs]

Available options are:

-profile     : name of the config file in C<../dicom-archive/.loris_mri> (defaults to C<prod>).

-ignore      : when performing the file backup, ignore files that do not exist or are not readable
               (default is to abort if such a file is found). This option is ignored if C<-n> is used.
               
-nobackup    : do not backup the files produced by the imaging pipeline for the upload(s) passed on
               the command line (default is to perform a backup).
               
-uploadID    : comma-separated list of upload IDs (in table C<mri_upload>) to delete.


=head1 DESCRIPTION

This program deletes all the files and database records produced by the imaging pipeline for a given set
of imaging uploads that have the same C<TarchiveID> in table C<mri_upload>. The script will issue and error
message and exit if multiple upload IDs are passed on the command line and they do not all have the 
same C<TarchiveID>. The script will remove the records associated to the imaging upload whose IDs are passed
on the command line from the following tables: C<notification_spool>, C<tarchive_series>
C<tarchive_files>, C<files_intermediary>, C<parameter_file>, C<files>, C<mri_violated_scans>
C<mri_violations_log>, C<MRICandidateErrors>, C<mri_upload> and C<tarchive>. It will also delete from
the file system the files that are associated to the upload and are listed in tables C<files>
C<files_intermediary>, C<parameter_file>, C<MRICandidateErrors>, C<mri_violations_log>
C<mri_protocol_violated_scans> along with the archive itself, whose path is stored in 
table C<tarchive>. The script will abort and will not delete anything if there is QC information
associated to the upload(s) (i.e entries in tables C<files_qcstatus> or C<feedback_mri_comments>).
If the script finds a file that is listed in the database but that does not exist on the file system or
is not readable, the script will issue an error message and abort, leaving the file system and database
untouched. This behaviour can be changed with option C<-ignore>. By default, the script will create a
backup of all the files that it plans to delete before actually deleting them. Use option C<-nobackup>
to perform a 'hard' delete (i.e. no backup). The backup file name will be C<< mri_upload.<UPLOAD_ID>.tar.gz >>.
Note that the file paths inside this backup archive are absolute.

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
my $uploadIDList   = undef;


my @opt_table = (
    ['-profile' , 'string'  , 1, \$profile, 
     'name of config file in ../dicom-archive/.loris_mri (defaults to "prod")'],
    ['-ignore'  , 'const'   , 0, \$dieOnFileError, 
     'When performing the file backup, ignore files that do not exist or are not readable.'
     . ' Default is to abort if such a file is found.'],
    ['-nobackup', 'const'   , 0, \$noBackup,
     'Do not backup anything. Default is to backup all files to be deleted '
     . 'into an archive named "mri_upload.<uploadID>.tar.gz", in the '
     . 'current directory'],
    ['-uploadID', 'string', 1, \$uploadIDList,
     'comma-separated list of upload IDs to delete. All the uploads must be associated to the same archive.']
);

my $Help = <<HELP;
HELP

my $usage = <<USAGE;
Usage: $0 [-profile profile] [-ignore] [-nobackup] [-uploadID uploadID]
USAGE

&Getopt::Tabular::SetHelp($Help, $usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

if(@ARGV != 0) {
    print STDERR "$usage\n";
    exit $NeuroDB::ExitCodes::INVALID_ARG;
}

if(!defined $uploadIDList) {
    print STDERR "Missing -uploadID option\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}

# Split the comma-separated string into a list of numbers
my @uploadID = split(',', $uploadIDList);

# Eliminate duplicate IDs
my %uploadID = map { $_ => 1 } @uploadID;
@uploadID = keys %uploadID;


#======================================#
# Validate all command line arguments  #
#======================================#
if(grep(!/\d+/, @uploadID)) {
    print STDERR "Argument to -uploadID option has to be a comma-separated list of numbers\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}

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

my $query = "SELECT m.UploadID, m.TarchiveID, t.ArchiveLocation, m.SessionID "
    .       "FROM mri_upload m "
    .       "JOIN tarchive t USING (TarchiveID) "
    .       "WHERE m.UploadID IN ("
    .       join(',', ('?') x @uploadID)
    .       ")";
my $uploadsRef = $dbh->selectall_hashref($query, 'UploadID', { 'Slice' => 1 }, @uploadID);

#======================================================#
# Check that all upload IDs passed on the command line #
# were found in the database                           #
#======================================================#
if(keys %$uploadsRef != @uploadID) {
    foreach(@uploadID) {
        if(!defined $uploadsRef->{$_}) {
            printf STDERR "No upload found in table mri_upload with upload ID $_\n";
            exit $NeuroDB::ExitCodes::INVALID_ARG;
        }
    }
}
my %tarchiveID = map { $uploadsRef->{$_}->{'TarchiveID'} => 1 } keys %$uploadsRef;

if(keys %tarchiveID != 1) {
    print STDERR "The upload IDs passed on the command line have different TarchiveIDs: ";
    print STDERR join(',', keys %tarchiveID);
    print STDERR ". Aborting\n";
    exit $NeuroDB::ExitCodes::INVALID_ARG;
}

# Since they are all the same, we can check the TarchiveID of the first
# upload
my $tarchiveID = (keys %tarchiveID)[0];
if(!$tarchiveID) {
    print STDERR "No tarchive ID found in table mri_upload for the uploads IDs passed on the command line\n";
    exit $NeuroDB::ExitCodes::INVALID_ARG;
}

my $archiveLocation = (values %$uploadsRef)[0]->{'ArchiveLocation'};
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

if(&hasQcOrComment($dbh, $tarchiveID)) {
    print STDERR "Cannot delete upload(s) passed on command line: there is QC information"
        . " defined on the MINC files for the associated tarchive (ID=$tarchiveID)\n";
    exit $NeuroDB::ExitCodes::INVALID_ARG;
}


#=================================================================#
# Find the absolute paths of all files associated to the          #
# upload(s) passed on the command lines in tables files           #
# files_intermediary, parameter_file, mri_protocol_violated_scans #
# mri_violations_log and MRICandidateErrors                       #
#=================================================================#
my %filePaths;
$filePaths{'files'}                       = &getFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$filePaths{'files_intermediary'}          = &getIntermediaryFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$filePaths{'parameter_file'}              = &getParameterFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$filePaths{'mri_protocol_violated_scans'} = &getMriProtocolViolatedScansFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$filePaths{'mri_violations_log'}          = &getMriViolationsLogFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$filePaths{'MRICandidateErrors'}          = &getMRICandidateErrorsFilesRef($dbh, $tarchiveID, $dataDirBasepath);

#================================================================#
# Backup all files found in the step above if that was requested #
#================================================================#
unless($noBackup) {
    &backupFiles($archiveLocation, \%filePaths, $tarchiveID);
}

#=======================================================#
# Delete everything associated to the upload(s) in the  #
# database                                              #
#=======================================================#
&deleteUploadsInDatabase($dbh, $uploadsRef, $tarchiveID, \%filePaths);

#=======================================================#
# Delete everything associated to the upload(s) in the  #
# file system                                           #
#=======================================================#
&deleteUploadsOnFileSystem($archiveLocation, \%filePaths);

printf ("Upload(s) %s successfully deleted.\n", join(', ', @uploadID));
exit $NeuroDB::ExitCodes::SUCCESS;

=pod

=head3 hasQcOrComment($dbh, $tarchiveID)

Determines if any of the MINC files associated to the C<tarchive> have QC 
information associated to them by looking at the contents of tables 
C<files_qcstatus> and C<feedback_mri_comments>.

INPUTS:
  - $dbh: database handle reference.
  - $tarchiveID: ID of the DICOM archive.

RETURNS:
  - 1 if there is QC information associated to the DICOM archive, 0 otherwise.

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
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting C<dataDirBasePath>.

RETURNS: 
 - an array of hash references. Each hash has two keys: C<FileID> => ID of a file in table C<files>
 and C<File> => absolute path of the file with the given ID.

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
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting C<dataDirBasePath>.

RETURNS: 
  - an array of hash references. Each hash has three keys: C<IntermedID> => ID of a file in 
  table C<files_intermediary>, C<FileID> => ID of this file in table C<files> and 
  C<File> => absolute path of the file with the given ID.

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

=head3 getParameterFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Gets the absolute paths of all the files associated to an archive that are listed in table
C<parameter_file> and have a parameter type set to C<check_pic_filename>.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting C<dataDirBasePath>.

RETURNS: 
  - an array of hash references. Each hash has two keys: C<FileID> => FileID of a file 
  in table C<parameter_file> and C<Value> => absolute path of the file with the given ID.

=cut
sub getParameterFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # Get all files in parameter_file with parameter_type set to
    # 'check_pic_filename' that are tied (indirectly) to the tarchive
    # with ID $tarchiveId
    (my $query =<<QUERY) =~ s/\s+/ /g;
        SELECT FileID, Value FROM parameter_file pf
        JOIN files f USING (FileID)
        JOIN parameter_type AS pt
        USING (ParameterTypeID)
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

=head3 getMriProtocolViolatedScansFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table C<mri_protocol_violated_scans>.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting C<dataDirBasePath>.

RETURNS: 
 - an array of hash references. Each hash has one key: C<minc_location> => location (absolute path)
 of a MINC file found in table C<mri_protocol_violated_scans>.

=cut
sub getMriProtocolViolatedScansFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # Get FileID and File path of each files in files directly tied
    # to $tarchiveId
    $query = 'SELECT minc_location FROM mri_protocol_violated_scans WHERE TarchiveID = ?';
    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

    # Make sure all paths are absolute paths
    foreach(@$filesRef) {
        $_->{'minc_location'} = "$dataDirBasePath/trashbin/$_->{'minc_location'}" unless $_->{'minc_location'} =~ /^\//;
    } 
    
    return $filesRef;   
}

=pod

=head3 getMriViolationsLogFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table C<mri_violations_log>.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting C<dataDirBasePath>.

RETURNS: 
 an array of hash references. Each hash has one key: C<MincFile> => location (absolute path)
 of a MINC file found in table C<mri_violations_log>.

=cut
sub getMriViolationsLogFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # Get file path of each files in files directly tied
    # to $tarchiveId
    $query = 'SELECT MincFile FROM mri_violations_log WHERE TarchiveID = ?';
    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

    # Make sure all paths are absolute paths
    foreach(@$filesRef) {
        $_->{'MincFile'} = "$dataDirBasePath/trashbin/$_->{'MincFile'}" unless $_->{'MincFile'} =~ /^\//;
    } 
    
    return $filesRef;   
}

=pod

=head3 getMRICandidateErrorsFilesRef($dbh, $tarchiveID, $dataDirBasePath)

Get the absolute paths of all the files associated to an archive that are listed in 
table C<MRICandidateErrors>.

INPUTS:
  - $dbhr  : database handle reference.
  - $tarchiveID: ID of the DICOM archive.
  - $dataDirBasePath: config value of setting C<dataDirBasePath>.

RETURNS: 
 - an array of hash references. Each hash has one key: C<MincFile> => location (absolute path)
 of a MINC file found in table C<MRICandidateErrors>.

=cut
sub getMRICandidateErrorsFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # Get file path of each files in files directly tied
    # to $tarchiveId
    $query = 'SELECT MincFile FROM MRICandidateErrors WHERE TarchiveID = ?';
    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

    # Make sure all paths are absolute paths
    foreach(@$filesRef) {
        $_->{'MincFile'} = "$dataDirBasePath/trashbin/$_->{'MincFile'}" unless $_->{'MincFile'} =~ /^\//;
    } 
    
    return $filesRef;   
}
=pod

=head3 getBackupFileName

Gets the name of the backup compressed file that will contain a copy of all the files
that the script will delete.

INPUTS:
  - $tarchiveID: ID of the DICOM archive (in table C<tarchive>) associated to the upload(s) passed on the command line.


RETURNS: 
  - backup file name.

=cut
sub getBackupFileName {
    my($tarchiveID) = @_;
    
    return "imaging_upload.$tarchiveID.tar.gz";
}

=pod

=head3 backupFiles($archiveLocation, $filePathsRef)

Backs up all the files associated to the archive before deleting them. The backed up files will
be stored in a C<.tar.gz> archive where all paths are relative to C</> (i.e absolute paths).

INPUTS:
  - $archiveLocation: full path of the archive associated to the upload(s) passed on the
                      command line (computed using the C<ArchiveLocation> value in table 
                      C<tarchive> for the given archive).
  - $filePathsRef: reference to the array that contains the absolute paths of all files found in tables
                   C<files>, C<files_intermediary>, C<parameter_file>, C<mri_protocol_violated_scans>
                   C<mri_violations_log> and C<MRICandidateErrors> that are tied to the upload(s) passed
                   on the command line.
  - $tarchiveID: ID of the DICOM archive (in table C<tarchive>) associated to the upload(s) passed on the command line.
                 
=cut
sub backupFiles {
    my($archiveLocation, $filePathsRef, $tarchiveID) = @_;
    
    # Put in @files the absolutes paths of all files in tables files, files_intermediary
    # parameter_file, mri_protocol_violated_scans, mri_violations_log and MRICandidateErrors
    # that are tied to the upload(s). Also put in @files the archive itself (found in table tarchive).
    my @files;
    push(@files, map { $_->{'File'} }          @{ $filePathsRef->{'files'} });
    push(@files, map { $_->{'File'} }          @{ $filePathsRef->{'files_intermediary'} });
    push(@files, map { $_->{'Value'} }         @{ $filePathsRef->{'parameter_file'} });
    push(@files, map { $_->{'minc_location'} } @{ $filePathsRef->{'mri_protocol_violated_scans'} });
    push(@files, map { $_->{'MincFile'} }      @{ $filePathsRef->{'mri_violations_log'} });
    push(@files, map { $_->{'MincFile'} }      @{ $filePathsRef->{'MRICandidateErrors'} });
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
    my $filesBackupPath = &getBackupFileName($tarchiveID);
    print "Backing up files related to the upload(s) to delete...\n";
    if(system('tar', 'zcvf', $filesBackupPath, '--absolute-names', '--files-from', $tmpFileName)) {
        print STDERR "backup command failed: $!\n";
        exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
    } 

    print "File $filesBackupPath successfully created.\n";
}

=pod

=head3 deleteUploadsInDatabase($dbh, $uploadsRef, $tarchiveID, $filePathsRef)

This method deletes all information in the database associated to the given upload(s). More specifically, it 
deletes records from tables C<notification_spool>, C<tarchive_files>, C<tarchive_series>, C<files_intermediary>,
C<parameter_file>, C<files>, C<mri_protocol_violated_scans>, C<mri_violations_log>, C<MRICandidateErrors>
C<mri_upload> and C<tarchive>. It will also set the C<Scan_done> value of the scan's session to 'N' for each upload
that is the last upload tied to that session. All the delete/update operations are done inside a single transaction so 
either they all succeed or they all fail (and a rollback is performed).

INPUTS:
  - $dbh       : database handle.
  - $uploadsRef: reference on a hash of hashes containing the uploads to delete. Accessed like this:
                 C<< $uploadsRef->{'1002'}->{'TarchiveID'} >>(this would return the C<TarchiveID> of the C<mri_upload>
                 with ID 1002). The properties stored for each hash are: C<UploadID>, C<TarchiveID>, C<ArchiveLocation>
                 and C<SessionID>.
  - $tarchiveID: ID of the DICOM archive to delete.
  - $filePathsRef: reference to the array that contains the absolute paths of all files found in tables
                   C<files>, C<files_intermediary>, C<parameter_file>, C<mri_protocol_violated_scans>
                   C<mri_violations_log> and C<MRICandidateErrors> that are tied to the upload(s) passed
                   on the command line.
                  
=cut
sub deleteUploadsInDatabase {
    my($dbh, $uploadsRef, $tarchiveID, $filePathsRef)= @_;
    
    $dbh->{'AutoCommit'} = 0;
    
    my $query = "DELETE FROM notification_spool WHERE ProcessID IN ("
              . join(',', ('?') x keys %$uploadsRef)
              . ")";
    $dbh->do($query, undef, keys %$uploadsRef);
    
    $query = "DELETE FROM tarchive_files WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    $query = "DELETE FROM tarchive_series WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    if(@{ $filePathsRef->{'parameter_file'} }) {
        my @parameterFileIDs = map { $_->{'FileID'} } @{ $filePathsRef->{'parameter_file'} };
        $query  = sprintf(
            "DELETE FROM parameter_file WHERE FileID IN (%s)",
            join(',', ('?') x @parameterFileIDs)
        );
        $dbh->do($query, undef, @parameterFileIDs);
    }

    my @intermediaryFileIDs = map { $_->{'IntermedID'} } @{ $filePathsRef->{'files_intermediary'} };
    if(@intermediaryFileIDs) {
        $query = sprintf(
            'DELETE FROM files_intermediary WHERE IntermedID IN (%s)', 
            join(',', ('?') x @intermediaryFileIDs)
        );
        $dbh->do($query, undef, @intermediaryFileIDs);     

        my @fileID = map { $_->{'FileID'} } @{ $filePathsRef->{'files_intermediary'} };
        $query = sprintf(
            "DELETE FROM files WHERE FileID IN (%s)",
            join(',', ('?') x @fileID)
        );
        $dbh->do($query, undef, @fileID);
    }
            
    $query = "DELETE FROM files WHERE TarchiveSource = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    $query = "DELETE FROM mri_protocol_violated_scans WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    $query = "DELETE FROM mri_violations_log WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    $query = "DELETE FROM MRICandidateErrors WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    $query = sprintf(
        "DELETE FROM mri_upload WHERE UploadID IN (%s)",
        join(',', map { '?' } keys %$uploadsRef)
    );
    $dbh->do($query, undef, keys %$uploadsRef);
    
    $query = "DELETE FROM tarchive WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    # If any of the upload to delete is the last upload that was part of the 
    # session associated to it, then set the session's 'Scan_done' flag
    # to 'N'.
    my @sessionIDs = map { $uploadsRef->{'SessionID'} } keys %$uploadsRef;
    $query = "UPDATE session s SET Scan_done = 'N'"
           . " WHERE s.ID IN ("
           . join(',', ('?') x @sessionIDs)
           . ") AND (SELECT COUNT(*) FROM mri_upload m WHERE m.SessionID=s.ID) = 0";
    $dbh->do($query, undef, map { $_->{'SessionID'} } @sessionIDs );
    
    $dbh->commit;
    $dbh->{'AutoCommit'} = 0;
}

=pod

=head3 deleteUploadsOnFileSystem($archiveLocation, $filePathsRef)

This method deletes from the file system all the files in tables C<files>, C<files_intermediary>
and C<parameter_file> associated to the upload(s) passed on the command line. The archive
found in table C<tarchive> tied to all the upload(s) passed on the command line is also delete. 
A warning is issued for any file that could not be deleted.

INPUTS:
  - $archiveLocation: full path of the archive associated to the upload(s) passed on the
                      command line (computed using the C<ArchiveLocation> value in table 
                      C<tarchive> for the given archive).
  - $filePathsRef: reference to the array that contains the absolute paths of all files found in tables
                   C<files>, C<files_intermediary>, C<parameter_file>, C<mri_protocol_violated_scans>
                   C<mri_violations_log> and C<MRICandidateErrors> that are tied to the upload(s) passed
                   on the command line.
                  
=cut
sub deleteUploadsOnFileSystem {
    my($archiveLocation, $filePathsRef) = @_;
    
    # Delete all files. A warning will be issued for every file that could not be
    # deleted
    NeuroDB::MRI::deleteFiles( map { $_->{'File'} }          @{ $filePathsRef->{'files'} });
    NeuroDB::MRI::deleteFiles( map { $_->{'File'} }          @{ $filePathsRef->{'files_intermediary'} });
    NeuroDB::MRI::deleteFiles( map { $_->{'Value'} }         @{ $filePathsRef->{'parameter_file'} });
    NeuroDB::MRI::deleteFiles( map { $_->{'minc_location'} } @{ $filePathsRef->{'mri_protocol_violated_scans'} });
    NeuroDB::MRI::deleteFiles( map { $_->{'MincFile'} }      @{ $filePathsRef->{'mri_violations_log'} });
    NeuroDB::MRI::deleteFiles( map { $_->{'MincFile'} }      @{ $filePathsRef->{'MRICandidateErrors'} });
    
    # Delete the backed up archive
    NeuroDB::MRI::deleteFiles($archiveLocation);
}










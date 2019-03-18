#!/usr/bin/perl

=pod

=head1 NAME

delete_mri_upload.pl -- Delete everything that was produced by the imaging pipeline for a given set of imaging uploads

=head1 SYNOPSIS

perl delete_mri_upload.pl [-profile file] [-ignore] [-nobackup] [-protocol] [-form] [-uploadID lis_of_uploadIDs]

Available options are:

-profile     : name of the config file in C<../dicom-archive/.loris_mri> (defaults to C<prod>).

-ignore      : ignore files whose paths exist in the database but do not exist on the file system.
               Default is to abort if such a file is found, irrespective of whether a backup has been
               requested or not (see C<-nobackup>). If this options is used, a warning is issued
               and program execution continues.
               
-nobackup    : do not backup the files produced by the imaging pipeline for the upload(s) passed on
               the command line (default is to perform a backup).
               
-uploadID    : comma-separated list of upload IDs (found in table C<mri_upload>) to delete. Program will 
               abort if the the list contains an upload ID that does not exist. Also, all upload IDs must
               have the same C<tarchive> ID.
               
-protocol    : delete the imaging protocol(s) in table C<mri_processing_protocol> associated to either the
               upload(s) specified via the C<-uploadID> option or any file that was produced using this (these)
               upload(s). Let F be the set of files directly or indirectly associated to the upload(s) to delete.
               This option must be used if there is at least one record in C<mri_processing_protocol> that is tied
               only to files in F. Protocols that are tied to files not in F are never deleted. If the files in F
               do not have a protocol associated to them, the switch is ignored if used.
               
-form        : delete the entries in C<mri_parameter_form> associated to the upload(s) passed on
               the command line, if any (default is NOT to delete them).

=head1 DESCRIPTION

This program deletes all the files and database records produced by the imaging pipeline for a given set
of imaging uploads that have the same C<TarchiveID> in table C<mri_upload>. The script will issue an error
message and exit if multiple upload IDs are passed on the command line and they do not all have the 
same C<TarchiveID> or if one of the upload ID does not exist. The script will remove the records associated
to the imaging upload whose IDs are passed on the command line from the following tables:
C<notification_spool>, C<tarchive_series>, C<tarchive_files>, C<files_intermediary>, C<parameter_file>
C<files>, C<mri_violated_scans>, C<mri_violations_log>, C<MRICandidateErrors>, C<mri_upload> and C<tarchive>.
In addition, entries in C<mri_processing_protocol> and C<mri_parameter_form> will be deleted if the switches
C<-protocol> and C<-form> are used, respectively. The script will also delete from the file system the files 
found in this set of tables (including the archive itself). No deletion will take place and the script will abort
if there is QC information associated to the upload(s) (i.e entries in tables C<files_qcstatus> or 
C<feedback_mri_comments>). If the script finds a file that is listed in the database but that does not exist on
the file system, the script will issue an error message and exit, leaving the file system and database untouched.
This behaviour can be changed with option C<-ignore>. By default, the script will create a backup of all the files
that it plans to delete before actually deleting them. Use option C<-nobackup> to perform a 'hard' delete (i.e. no
backup). The backup file name will be C<< imaging_upload.<TARCHIVE_ID>.tar.gz >>. Note that the file paths inside
this backup archive are absolute. To restore the files in the archive, one must use C<tar> with option C<--absolute-names>.

=head2 Methods

=cut

use strict;
use warnings;

use NeuroDB::DBI;
use NeuroDB::ExitCodes;
use NeuroDB::MRI;

use Getopt::Tabular;       

use File::Temp qw/tempfile/;

use constant DEFAULT_PROFILE                   => 'prod';
use constant DEFAULT_DIE_ON_FILE_ERROR         => 1;
use constant DEFAULT_NO_BACKUP                 => 0;
use constant DEFAULT_DELETE_PROTOCOLS          => 0;
use constant DEFAULT_DELETE_MRI_PARAMETER_FORM => 0;

use constant PIC_SUBDIR                => 'pic';

# These are the tables that contain references to files related to the uploads.
# Note that the script also deletes entries in mri_parameter_form even though
# this table is not listed here.
my @PROCESSED_TABLES = (
    'files',
    'files_intermediary',
    'parameter_file',
    'mri_protocol_violated_scans',
    'mri_violations_log',
    'MRICandidateErrors',
    'tarchive',
    'mri_processing_protocol'
);

my $profile                = DEFAULT_PROFILE;
my $dieOnFileError         = DEFAULT_DIE_ON_FILE_ERROR;
my $noBackup               = DEFAULT_NO_BACKUP;
my $deleteProtocols        = DEFAULT_DELETE_PROTOCOLS;
my $deleteMriParameterForm = DEFAULT_DELETE_MRI_PARAMETER_FORM;
my $uploadIDList           = undef;

my @opt_table = (
    ['-profile' , 'string'  , 1, \$profile, 
     'Name of config file in ../dicom-archive/.loris_mri (defaults to "prod")'],
    ['-ignore'  , 'const'   , 0, \$dieOnFileError, 
     'Ignore files that exist in the database but not on the file system.'
     . ' Default is to abort if such a file is found.'],
    ['-nobackup', 'const'   , 1, \$noBackup,
     'Do not backup anything. Default is to backup all files to be deleted '
     . 'into an archive named "imaging_upload.<TarchiveID>.tar.gz", in the '
     . 'current directory'],
    ['-uploadID', 'string', 1, \$uploadIDList,
     'Comma-separated list of upload IDs to delete. All the uploads must be associated to the same archive.'],
    ['-protocol', 'const', 1, \$deleteProtocols,
     'Delete the entries in mri_processing_protocols tied to the upload(s) specified via -uploadID.'],
    ['-form', 'const', 1, \$deleteMriParameterForm,
     'Delete the entries in mri_parameter_form tied to the upload(s) specified via -uploadID.']
);

my $Help = <<HELP;
HELP

my $usage = <<USAGE;
Usage: $0 [-profile profile] [-ignore] [-nobackup] [-protocol] [-form] [-uploadID uploadIDList]
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

#====================================#
# Establish database connection.     #
#====================================#
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# Die as soon as a DB operation fails. As a side-effect, any transaction that has not
# been commited at that point will automatically be rolled back
$dbh->{'RaiseError'} = 1;

# Do not print an error message when a DB error occurs since the error message 
# will be printed when the program dies anyway 
$dbh->{'PrintError'} = 0;

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
# mri_violations_log, MRICandidateErrors and tarchive             #
#=================================================================#
my %files;
$files{'files'}                       = &getFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$files{'files_intermediary'}          = &getIntermediaryFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$files{'parameter_file'}              = &getParameterFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$files{'mri_protocol_violated_scans'} = &getMriProtocolViolatedScansFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$files{'mri_violations_log'}          = &getMriViolationsLogFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$files{'MRICandidateErrors'}          = &getMRICandidateErrorsFilesRef($dbh, $tarchiveID, $dataDirBasepath);
$files{'tarchive'}                    = [ 
    {
        'FullPath'        => $archiveLocation =~ /^\// 
            ? $archiveLocation : "$tarchiveLibraryDir/$archiveLocation",
        'ArchiveLocation' => $archiveLocation,
        'TarchiveID'      => $tarchiveID
    }
];
$files{'mri_processing_protocol'}     = &getMriProcessingProtocolFilesRef($dbh, \%files);


#========================================================================#
# Make sure that -protocol option is used if:                            #
# 1. There is at least one processing protocol associated to the files   #
#    to delete.                                                          #
# 2. This protocol is associated *only* to one or more of the files that #
#    are going to deleted.                                               #
#========================================================================#
if(@{ $files{'mri_processing_protocol'} } && !$deleteProtocols) {
    my $msg = sprintf(
        "%s found for the %s to delete: you must use -protocol\n",
        (@{ $files{'mri_processing_protocol'} } > 1 ? 'Processing protocols' : 'Processing protocol'),
        (@uploadID > 1 ? 'uploads' : 'upload')
    );
    die "$msg\n";
}

#=============================================================================#
# Verify that all files found in the various tables exist on the file system  #
#=============================================================================#

my $missingFilesRef = &setFileExistenceStatus(\%files);
if(@$missingFilesRef) {
    my $msg;
    if(@$missingFilesRef == 1) {
        $msg = "File $missingFilesRef->[0] exists in the database but was not found on the file system.";
    } else {
        $msg= "The following files exist in the database but were not found on the file system:\n";
        foreach(@$missingFilesRef) {
            $msg .= "\t$_\n";
        }
    }
    
    die "Error! $msg\nAborting.\n" if $dieOnFileError;
    print STDERR "Warning! $msg\n";
}

&backupFiles(\%files) unless $noBackup;

#=======================================================#
# Delete everything associated to the upload(s) in the  #
# database                                              #
#=======================================================#
&deleteUploadsInDatabase($dbh, $uploadsRef, \%files, $deleteMriParameterForm);

#=======================================================#
# Delete everything associated to the upload(s) in the  #
# file system                                           #
#=======================================================#
&deleteUploadsOnFileSystem(\%files);

#==========================#
# Print success message    #
#==========================#
my $uploadIdsString = join(', ', @uploadID);
$uploadIdsString =~ s/, (\d+)$/ and $1/;
printf(
    "%s %s successfully deleted.\n",
    (@uploadID > 1 ? 'Uploads' : 'Upload'),
    $uploadIdsString
);
exit $NeuroDB::ExitCodes::SUCCESS;

=pod

=head3 getMriProcessingProtocolFilesRef($dbh, $filesRef)

Finds the list of C<ProcessingProtocolID> to delete, namely those in table
C<mri_processing_protocol> associated to the files to delete, and *only* to 
those files that are not going to be deleted.

INPUTS:
  - $dbh: database handle reference.
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.

RETURNS:
 - reference on an array that contains the C<ProcessingProtocolID> in table C<mri_processing_protocol>
   associated to the files to delete. This array has two keys: C<ProcessProtocolID> => the protocol 
   process ID found table C<mri_processing_protocol> and C<FullPath> => the value of C<ProtocolFile>
   in the same table.

=cut

sub getMriProcessingProtocolFilesRef {
    my($dbh, $filesRef) = @_;
    
    my %fileID;
    foreach my $t (@PROCESSED_TABLES) {
        foreach my $f (@{ $filesRef->{$t} }) {
            $fileID{ $f->{'FileID'} } = 1 if defined $f->{'FileID'};
        }
    }
    
    return [] if !%fileID;
    
    my $query = 'SELECT DISTINCT(mpp.ProcessProtocolID), mpp.ProtocolFile AS FullPath '
              . 'FROM files f '
              . 'JOIN mri_processing_protocol mpp USING (ProcessProtocolID) '
              . 'WHERE f.FileID IN ('
              . join(',', ('?') x keys %fileID)
              . ') AND f.ProcessProtocolID IS NOT NULL';
    
    # This varaiable will contain all the protocols associated to the files that will be
    # deleted. Note that these protocols might also be associated to files that are *not* 
    # going to be deleted
    my $protocolsRef = $dbh->selectall_arrayref($query, { 'Slice' => {} }, keys %fileID);
    
    return [] unless @$protocolsRef;
    
    # Now get the list of protocols in @$protocolsRef that are also associated to files
    # that are not going to de deleted
    $query = 'SELECT ProcessProtocolID '
           . 'FROM files '
           . 'WHERE ProcessProtocolID IN ('
           . join(',', ('?') x @$protocolsRef)
           . ') '
           . 'AND FileID NOT IN ('
           . join(',', ('?') x keys %fileID)
           . ')';
    
    my $protocolsNotDeletedRef = $dbh->selectcol_arrayref(
        $query, 
        { 'Columns' => [1] },
        (map { $_->{'ProcessProtocolID'} } @$protocolsRef), 
        keys %fileID
    );
    
    # Eliminate from @$protocolsRef the entries of that are also in @$protocolsNotDeletedRef
    for(my $i=$#{ $protocolsRef }; $i >= 0; $i--) { 
        if(grep($_ == $protocolsRef->[$i]->{'ProcessProtocolID'}, @$protocolsNotDeletedRef)) {
            splice(@$protocolsRef, $i, 1);
        }
    }
    
    return $protocolsRef;
}

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
 - an array of hash references. Each hash has three keys: C<FileID> => ID of a file in table C<files>
   C<File> => value of column C<File> for the file with the given ID and C<FullPath> => absolute path
   for the file with the given ID.

=cut
sub getFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # Get FileID and File path of each files in files directly tied
    # to $tarchiveId
    $query = 'SELECT FileID, File FROM files WHERE TarchiveSource = ?';
    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

    # Set full path of every file
    foreach(@$filesRef) {
        $_->{'FullPath'} = $_->{'File'} =~ /^\// 
            ? $_->{'File'} : "$dataDirBasePath/$_->{'File'}";
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
  - an array of hash references. Each hash has four keys: C<IntermedID> => ID of a file in 
  table C<files_intermediary>, C<FileID> => ID of this file in table C<files>, C<File> => value
  of column C<File> in table C<files> for the file with the given ID and C<FullPath> => absolute
  path of the file with the given ID.

=cut
sub getIntermediaryFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # This should get all files in table files_intermediary that are tied
    # indirectly to the tarchive with ID $tarchiveId
    my $query = 'SELECT fi.IntermedID, f.FileID, f.File FROM files_intermediary fi '
        .       'JOIN files f ON (fi.Output_FileID=f.FileID) '
        .       'WHERE f.SourceFileID IN (SELECT FileID FROM files WHERE TarchiveSource = ?)';

    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

    # Set full path of every file
    foreach(@$filesRef) {
        $_->{'FullPath'} = $_->{'File'} =~ /^\// 
            ? $_->{'File'} : "$dataDirBasePath/$_->{'File'}";
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
  - an array of hash references. Each hash has three keys: C<FileID> => FileID of a file 
  in table C<parameter_file>, C<Value> => value of column C<Value> in table C<parameter_file>
  for the file with the given ID and C<FullPath> => absolute path of the file with the given ID.

=cut
sub getParameterFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # Get all files in parameter_file with parameter_type set to
    # 'check_pic_filename' that are tied (indirectly) to the tarchive
    # with ID $tarchiveId
    (my $query =<<QUERY) =~ s/\s+/ /g;
        SELECT FileID, Value, pt.Name FROM parameter_file pf
        JOIN files f USING (FileID)
        JOIN parameter_type AS pt
        USING (ParameterTypeID)
        WHERE pt.Name IN ('check_pic_filename', 'check_nii_filename', 'check_bval_filename', 'check_bvec_filename')
        AND (
                f.TarchiveSource = ? 
             OR f.SourceFileID IN (SELECT FileID FROM files WHERE TarchiveSource = ?)
        )
QUERY

    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID, $tarchiveID);
    
    # Set full path of every file
    foreach(@$filesRef) {
        my $fileBasePath = $_->{'Name'} eq 'check_pic_filename'
            ? $dataDirBasePath . PIC_SUBDIR : $dataDirBasePath;
        $_->{'FullPath'} = $_->{'Value'} =~ /^\//
            ? $_->{'Value'} : sprintf("%s/%s", $fileBasePath, $_->{'Value'});
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
 - an array of hash references. Each hash has two keys: C<minc_location> => value of column C<minc_location>
 in table C<mri_protocol_violated_scans> for the MINC file found and C<FullPath> => absolute path of the MINC
 file found.

=cut
sub getMriProtocolViolatedScansFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # Get FileID and File path of each files in files directly tied
    # to $tarchiveId
    $query = 'SELECT minc_location FROM mri_protocol_violated_scans WHERE TarchiveID = ?';
    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

    # Set full path of every file
    foreach(@$filesRef) {
        $_->{'FullPath'} = $_->{'minc_location'} =~ /^\// 
            ? $_->{'minc_location'} : "$dataDirBasePath/$_->{'minc_location'}";
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
 an array of hash references. Each hash has two keys: C<MincFile> => value of column
 C<MincFile> for the MINC file found in table C<mri_violations_log> and C<FullPath> => absolute
 path of the MINC file.

=cut
sub getMriViolationsLogFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # Get file path of each files in files directly tied
    # to $tarchiveId
    $query = 'SELECT MincFile FROM mri_violations_log WHERE TarchiveID = ?';
    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

    # Set full path of every file
    foreach(@$filesRef) {
        $_->{'FullPath'} = $_->{'MincFile'} =~ /^\// 
            ? $_->{'MincFile'} : "$dataDirBasePath/$_->{'MincFile'}";
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
 - an array of hash references. Each hash has two keys: C<MincFile> => value of column
 C<MincFile> for the MINC file found in table C<MRICandidateErrors> and C<FullPath> => absolute
 path of the MINC file.

=cut
sub getMRICandidateErrorsFilesRef {
    my($dbh, $tarchiveID, $dataDirBasePath) = @_;
    
    # Get file path of each files in files directly tied
    # to $tarchiveId
    $query = 'SELECT MincFile FROM MRICandidateErrors WHERE TarchiveID = ?';
    my $filesRef = $dbh->selectall_arrayref($query, { Slice => {} }, $tarchiveID);

    # Set full path of every file
    foreach(@$filesRef) {
        $_->{'FullPath'} = $_->{'MincFile'} =~ /^\// 
            ? $_->{'MincFile'} : "$dataDirBasePath/$_->{'MincFile'}";
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

=head3 setFileExistenceStatus($filesRef)

Checks the list of all the files related to the upload(s) that were found in the database and 
builds the list of those that do not exist on the file system. 

INPUTS:
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.
  
RETURNS:
  - Reference on the list of files that do not exist on the file system.
                 
=cut
sub setFileExistenceStatus {
    my($filesRef, $protocolsRef) = @_;
    
    my @missingFiles;
    foreach my $t (@PROCESSED_TABLES) {
        foreach my $f (@{ $filesRef->{$t} }) {
            $f->{'Exists'} = -e $f->{'FullPath'};
            push(@missingFiles, $f->{'FullPath'}) if !$f->{'Exists'};
        }
    }
    
    return \@missingFiles;
}

=head3 backupFiles($filesRef)

Backs up all the files associated to the archive before deleting them. The backed up files will
be stored in a C<.tar.gz> archive where all paths are absolute.

INPUTS:
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.

RETURNS:
  - Reference on the list of files successfully backed up.
                 
=cut
    
sub backupFiles {
    my($filesRef) = @_;
    
    my $hasSomethingToBackup = 0;
    foreach my $t (@PROCESSED_TABLES) {
        last if $hasSomethingToBackup;
        $hasSomethingToBackup = grep($_->{'Exists'}, @{ $filesRef->{$t} });
    }
    
    return unless $hasSomethingToBackup;
    
    # Create a temporary file that will list the absolute paths of all
    # files to backup (archive). 
    my($fh, $tmpFileName) = tempfile("$0.filelistXXXX", UNLINK => 1);
    foreach my $t (@PROCESSED_TABLES) {
        foreach my $f (@{ $filesRef->{$t} }) {
            print $fh "$f->{'FullPath'}\n" unless !$f->{'Exists'};
        }
    }
    close($fh);
    
    # Put all files in a big compressed tar ball
    my $filesBackupPath = &getBackupFileName($filesRef->{'tarchive'}->[0]->{'TarchiveID'});
    print "\nBacking up files related to the upload(s) to delete...\n";
    if(system('tar', 'zcvf', $filesBackupPath, '--absolute-names', '--files-from', $tmpFileName)) {
        print STDERR "backup command failed: $!\n";
        exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
    } 

    print "File $filesBackupPath successfully created.\n";
}

=pod

=head3 deleteUploadsInDatabase($dbh, $uploadsRef, $filesRef)

This method deletes all information in the database associated to the given upload(s). More specifically, it 
deletes records from tables C<notification_spool>, C<tarchive_files>, C<tarchive_series>, C<files_intermediary>,
C<parameter_file>, C<files>, C<mri_protocol_violated_scans>, C<mri_violations_log>, C<MRICandidateErrors>
C<mri_upload> and C<tarchive>, C<mri_processing_protocol> and C<mri_parameter_form> (the later is done only if requested).
It will also set the C<Scan_done> value of the scan's session to 'N' for each upload that is the last upload tied to 
that session. All the delete/update operations are done inside a single transaction so either they all succeed or they 
all fail (and a rollback is performed).

INPUTS:
  - $dbh       : database handle.
  - $uploadsRef: reference on a hash of hashes containing the uploads to delete. Accessed like this:
                 C<< $uploadsRef->{'1002'}->{'TarchiveID'} >>(this would return the C<TarchiveID> of the C<mri_upload>
                 with ID 1002). The properties stored for each hash are: C<UploadID>, C<TarchiveID>, C<ArchiveLocation>
                 and C<SessionID>.
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.
  - $deleteForm: whether to delete the C<mri_parameter_form> entries associated to the upload(s) passed on the command line.
                  
=cut
sub deleteUploadsInDatabase {
    my($dbh, $uploadsRef, $filesRef, $deleteMriParameterForm)= @_;
    
    # This starts a DB transaction. All operations are delayed until
    # commit is called
    $dbh->begin_work;
    
    my $query = "DELETE FROM notification_spool WHERE ProcessID IN ("
              . join(',', ('?') x keys %$uploadsRef)
              . ")";
    $dbh->do($query, undef, keys %$uploadsRef);
    
    my $tarchiveID = $filesRef->{'tarchive'}->[0]->{'TarchiveID'};
    
    $query = "DELETE FROM tarchive_files WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    $query = "DELETE FROM tarchive_series WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    if(@{ $filesRef->{'parameter_file'} }) {
        my @parameterFileIDs = map { $_->{'FileID'} } @{ $filesRef->{'parameter_file'} };
        $query  = sprintf(
            "DELETE FROM parameter_file WHERE FileID IN (%s)",
            join(',', ('?') x @parameterFileIDs)
        );
        $dbh->do($query, undef, @parameterFileIDs);
    }

    my @intermediaryFileIDs = map { $_->{'IntermedID'} } @{ $filesRef->{'files_intermediary'} };
    if(@intermediaryFileIDs) {
        $query = sprintf(
            'DELETE FROM files_intermediary WHERE IntermedID IN (%s)', 
            join(',', ('?') x @intermediaryFileIDs)
        );
        $dbh->do($query, undef, @intermediaryFileIDs);

        my @fileID = map { $_->{'FileID'} } @{ $filesRef->{'files_intermediary'} };
        
        #==================================================================#
        # If there's anything in parameter_file associated to the files    #
        # deleted from files_intermediary, delete it also                  #
        #==================================================================#
       $query  = sprintf(
            "DELETE FROM parameter_file WHERE FileID IN (%s)",
            join(',', ('?') x @fileID)
        );
        
        $dbh->do($query, undef, @fileID);
        
        #================================================================#
        # Delete the entries in files associated to the entries deleted  #
        # from files_intermediary                                        #
        #================================================================#
        $query = sprintf(
            "DELETE FROM files WHERE FileID IN (%s)",
            join(',', ('?') x @fileID)
        );
        $dbh->do($query, undef, @fileID);
    }
            
    #===========================================================================#
    # Before deleting the files in table files with                             #
    # TarchiveSource=$tarchiveID, we have to delete any entry in parameter_file #
    # that is related to these files                                            #
    #===========================================================================#
    $query = "DELETE FROM parameter_file "
           . "WHERE FileID IN (SELECT FileID FROM files WHERE TarchiveSource = ?)";
    $dbh->do($query, undef, $tarchiveID);
        
    $query = "DELETE FROM files WHERE TarchiveSource = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    my @protocolIDs = map { $_->{'ProcessProtocolID'} } @{ $filesRef->{'mri_processing_protocol'} };
    if(@protocolIDs) {
        $query = sprintf(
            "DELETE FROM mri_processing_protocol WHERE ProcessProtocolID IN (%s)",
            join(',', ('?') x @protocolIDs)
        );
        $dbh->do($query, undef, @protocolIDs);
    }
 
    $query = "DELETE FROM mri_protocol_violated_scans WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    $query = "DELETE FROM mri_violations_log WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    $query = "DELETE FROM MRICandidateErrors WHERE TarchiveID = ?";
    $dbh->do($query, undef, $tarchiveID);
    
    # Delete the entries in mri_parameter_form and flag if requested
    if($deleteMriParameterForm) {
        $query = "DELETE FROM mri_parameter_form "
               . "WHERE CommentID IN ( "
               . "   SELECT f.CommentID FROM flag f "
               . "   JOIN session s ON (s.ID=f.SessionID) "
               . "   JOIN mri_upload mu ON (s.ID=mu.SessionID) "
               . "   WHERE f.Test_name='mri_parameter_form' "
               . "   AND mu.UploadID IN( " 
               .     join(',', map { '?' } keys %$uploadsRef)
               . "   ) "
               . ")";
        $dbh->do($query, undef, keys %$uploadsRef);

        $query = "DELETE FROM flag "
               . "WHERE test_name = 'mri_parameter_form' "
               . "AND SessionID IN ("
               . "   SELECT s.ID FROM session s "
               . "   JOIN mri_upload mu ON (s.ID=mu.SessionID) "
               . "   WHERE mu.UploadID IN( " 
               .     join(',', map { '?' } keys %$uploadsRef)
               . "   ) "
               . ")";
        $dbh->do($query, undef, keys %$uploadsRef);
    }
    
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
}

=pod

=head3 deleteUploadsOnFileSystem($filesRef)

This method deletes from the file system all the files associated to the upload(s) passed on the
command line that were found on the file system. The archive found in table C<tarchive> tied to all
the upload(s) passed on the command line is also deleted. A warning will be issued for any file that
could not be deleted.

INPUTS:
  - $filesRef: reference to the array that contains the file informations for all the files
  that are associated to the upload(s) passed on the command line.
                  
=cut
sub deleteUploadsOnFileSystem {
    my($filesRef) = @_;
    
    foreach my $t (@PROCESSED_TABLES) {
        foreach my $f (@{ $filesRef->{$t} }) {
            next unless $f->{'Exists'};
            NeuroDB::MRI::deleteFiles($f->{'FullPath'});
        }
    }
}

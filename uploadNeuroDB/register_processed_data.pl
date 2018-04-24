#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use FindBin;
use lib "$FindBin::Bin";

use NeuroDB::DBI;
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::ExitCodes;

use NeuroDB::Database;

my  $profile    = undef;
my  $filename;
my  $sourceFileID;
my  $tool;
my  $sourcePipeline;
my  $pipelineDate;
my  $coordinateSpace;
my  $scanType;
my  $outputType;
my  $inputFileIDs;
my  $protocolID;
my  @args;

my  $Usage  =   <<USAGE;

This script inserts processed data in the files and parameter_file tables. All options listed below are required as they will be necessary to insert a file in the DB.

Usage: perl register_processed_data.pl [options]

-help for options

USAGE

my  @args_table = (
    ["-profile",            "string",   1,  \$profile,          "name of config file in ../dicom-archive/.loris_mri."],
    ["-file",               "string",   1,  \$filename,         "file that will be registered in the database (full path from the root directory is required)"],
    ["-sourceFileID",       "string",   1,  \$sourceFileID,     "FileID of the raw input dataset that was processed to obtain the file to be registered in the database"],
    ["-sourcePipeline",     "string",   1,  \$sourcePipeline,   "Pipeline name that was used to obtain the file to be registered (example: DTIPrep_pipeline)"],
    ["-tool",               "string",   1,  \$tool,             "Tool name and version that was used to obtain the file to be registered (example: DTIPrep_v1.1.6)"],
    ["-pipelineDate",       "string",   1,  \$pipelineDate,     "Date the pipeline was run to obtain the file to be registered"],
    ["-coordinateSpace",    "string",   1,  \$coordinateSpace,  "Space coordinate of the file (i.e. linear, nonlinear or native)"],
    ["-scanType",           "string",   1,  \$scanType,         "The scan type of the file that is stored in the table mri_scan_type (i.e. QCedDTI, RGBqc, TxtQCReport, XMLQCReport...)"],
    ["-outputType",         "string",   1,  \$outputType,       "The type of output that will be registered in the database (i.e. QCed, processed, QCReport)"],
    ["-inputFileIDs",       "string",   1,  \$inputFileIDs,       "List of input fileIDs used to obtain the file to be registered (each entries being separated by ';')"],
    ["-protocolID",         "string",   1,  \$protocolID,       "ID of the registered protocol that was used to process data"]
);

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

# Input option error checking
if ( !$profile ) {
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if  ( !@Settings::db )    {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}

# Make sure we have all the arguments we need
unless  ($filename && $sourceFileID && $sourcePipeline && $scanType
         && $pipelineDate && $coordinateSpace && $outputType
         && $tool && $inputFileIDs)   {
    print STDERR "$Usage\n\tERROR: -file, -sourceFileID, -sourcePipeline, "
                 . "-scanType, -pipelineDate -coordinateSpace, -outputType, "
                 . "-tool & -inputFileIDs must be specified.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}

# Make sure sourceFileID is valid
unless  ((defined($sourceFileID)) && ($sourceFileID =~ /^[0-9]+$/)) {
    print STDERR "Files to be registered require the -sourceFileID option "
                 . "with a valid FileID as an argument\n";
    exit $NeuroDB::ExitCodes::INVALID_ARG;
}

# Make sure we have permission to read the file
unless  (-r $filename)  {
    print STDERR "Cannot read $filename\n";
    exit $NeuroDB::ExitCodes::INVALID_PATH;
}

# Establish database connection
my $dbh     =   &NeuroDB::DBI::connect_to_db(@Settings::db);

my $db = NeuroDB::Database->new(
    databaseName => $Settings::db[0],
    userName     => $Settings::db[1],
    password     => $Settings::db[2],
    hostName     => $Settings::db[3]
);
$db->connect();

# These settings are in the config file (profile)
my $data_dir = NeuroDB::DBI::getConfigSetting(
                    \$dbh,'dataDirBasepath'
                    );
my $pic_dir  =   $data_dir.'/pic';
my $jiv_dir  =   $data_dir.'/jiv';
my $prefix   = NeuroDB::DBI::getConfigSetting(
                    \$dbh,'prefix'
                    );
# Needed for log file
my  $log_dir    =   "$data_dir/logs/registerProcessed";
system("mkdir -p -m 770 $log_dir") unless (-e $log_dir);
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)    =   localtime(time);
my  $date       =   sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log        =   "$log_dir/registerProcessed$date.log";
open (LOG,">>$log");
print LOG "\n==> Successfully connected to database \n";
print LOG "Log file, $date\n\n";



# ----- STEP 1: Create and load File object.
# Create File object
my $file    =   NeuroDB::File->new(\$dbh);

# Load File object
$file->loadFileFromDisk($filename);

if  ($file->getFileDatum('FileType') eq 'mnc')  {
    
    # Map dicom fields
    &NeuroDB::MRI::mapDicomParameters(\$file);
    print LOG "\n==>Mapped DICOM parameters\n";

    # Optionally do extra filtering, if needed
    if  (defined(&Settings::filterParameters))  {
        print LOG "\t -> using user-defined filterParameters for $filename\n" ;
        Settings::filterParameters(\$file);     
    }
}


# ----- STEP 2: Verify PSC information using whatever field contains the site string 
#       (only for minc files)
my  ($center_name,$centerID);
if  ($file->getFileDatum('FileType') eq 'mnc')  {
    my  $lookupCenterName       =   NeuroDB::DBI::getConfigSetting(
                                    \$dbh,'lookupCenterNameUsing'
                                    );
    my  $patientInfo;
    if      ($lookupCenterName eq 'PatientName')    {
        $patientInfo    =   fetchMincHeader($filename,'patient:full_name');
    }elsif  ($lookupCenterName eq 'PatientID')      {
        $patientInfo    =   fetchMincHeader($filename,'patient:identification');
    }
    ($center_name, $centerID)   =   NeuroDB::MRI::getPSC($patientInfo, \$dbh);
    my  $psc    =   $center_name;
    if  (!$psc)     { 
        print LOG "\nERROR: No center found for this candidate \n\n"; 
        exit $NeuroDB::ExitCodes::SELECT_FAILURE;
    }
    print LOG  "\n==> Verifying acquisition center\n - Center Name  : $center_name\n - CenterID     : $centerID\n";
}


# ----- STEP 3: Determine ScannerID based: 
#                   - on mincheader information if minc file
#                   - on sourceFileID for other type of files
my $scannerID;

if  ($file->getFileDatum('FileType') eq 'mnc')  {
    my  %scannerInfo;
    my  $register_new   =   0;  # This does not allow to register new sanner since files are supposed to be children from files (and scanner)  already entered in the database. Should add it as an option? 
    $scannerInfo{'ScannerManufacturer'}     =   fetchMincHeader($filename,'study:manufacturer');
    $scannerInfo{'ScannerModel'}            =   fetchMincHeader($filename,'study:device_model');
    $scannerInfo{'ScannerSerialNumber'}     =   fetchMincHeader($filename,'study:serial_no');
    $scannerInfo{'ScannerSoftwareVersion'}  =   fetchMincHeader($filename,'study:software_version');
    $scannerID  =   NeuroDB::MRI::findScannerID($scannerInfo{'ScannerManufacturer'},
                                                $scannerInfo{'ScannerModel'},
                                                $scannerInfo{'ScannerSerialNumber'},
                                                $scannerInfo{'ScannerSoftwareVersion'},
                                                $centerID,\$dbh,0
                                                );
}else   {
    $scannerID  =   getScannerID($sourceFileID,$dbh);
}

if  (!defined($scannerID))  {
    print LOG "\nERROR: could not determine scannerID based on sourceFileID "
              . "$sourceFileID.\n\n";
    exit $NeuroDB::ExitCodes::SELECT_FAILURE;
}
$file->setFileData('ScannerID',$scannerID);
print LOG "\t -> Set ScannerID to $scannerID.\n";


# ----- STEP 4: Determine using sourceFileID: 
#                   - subject's identifiers 
#                   - sessionID 
#                   - requiresStaging 
my ($sessionID,$requiresStaging,$subjectIDsref)    =   getSessionID($sourceFileID,$dbh);
if  (!defined($sessionID))  {
    print LOG "\nERROR: could not determine sessionID based on sourceFileID "
              . "$sourceFileID. Are you sure the sourceFile was registered "
              . "in DB?\n\n";
    exit $NeuroDB::ExitCodes::SELECT_FAILURE;
}
print LOG "\n==> Data found for candidate   : $subjectIDsref->{'CandID'} - Visit: $subjectIDsref->{'visitLabel'}\n";
$file->setFileData('SessionID', $sessionID);
print LOG "\t -> Set SessionID to $sessionID.\n";
$file->setFileData('SourceFileID', $sourceFileID);
print LOG "\t -> Set SourceFileID to $sourceFileID.\n";


# ----- STEP 5: Determine AcquisitionProtocolID based on $scanType
my  ($acqProtID)    =   getAcqProtID($scanType,$dbh);
if  (!defined($acqProtID))  {
    print LOG "\nERROR: could not determine AcquisitionProtocolID based on scanType $scanType.\n\n";
    exit $NeuroDB::ExitCodes::UNKNOWN_PROTOCOL;
}
$file->setFileData('AcquisitionProtocolID',$acqProtID);
print LOG "\t -> Set AcquisitionProtocolID to $acqProtID.\n";


# ----- STEP 6: Set other parameters based on command line arguments
$file->setFileData('CoordinateSpace',$coordinateSpace);
print LOG "\t -> Set CoordinateSpace to $coordinateSpace.\n";
$file->setFileData('SourcePipeline',$sourcePipeline);
print LOG "\t -> Set SourcePipeline to $sourcePipeline.\n";
$file->setFileData('PipelineDate',$pipelineDate);
print LOG "\t -> Set PipelineDate to $pipelineDate.\n";
$file->setFileData('OutputType',$outputType);
print LOG "\t -> Set OutputType to $outputType.\n";
if ($protocolID) {
    $file->setFileData('ProcessProtocolID', $protocolID);
    print LOG "\t -> Set ProcessProtocolID to $protocolID.\n";
}

# ----- STEP 7: Compute the md5 hash
my  $md5hash    =   &NeuroDB::MRI::compute_hash(\$file);
$file->setParameter('md5hash', $md5hash);
print LOG "\t -> Set md5hash to $md5hash.\n";
if  (!NeuroDB::MRI::is_unique_hash(\$file)) {
    print LOG "\n==> $file is not a unique file and will not be added to database.\n\n";
    exit $NeuroDB::ExitCodes::FILE_NOT_UNIQUE;
}


# ----- STEP 8: Copy files to assembly folder and register them into the db.
# Rename and copy file into assembly folder
my $file_protocol_identified    =   &copy_file(\$filename, $subjectIDsref, $scanType, \$file);
my $file_path   =   $filename; 
$file_path      =~  s/$data_dir\///i;
print "new NAME: ".$file_protocol_identified ."\n";
$file->setFileData('File', $file_path);

# register into the db
my  $fileID;
$fileID     =   &NeuroDB::MRI::register_db(\$file);

# if we don't have a valid MRIID
unless  ($fileID)   {
    # tell the user something went wrong
    print LOG "\n==> FAILED TO REGISTER FILE $filename!\n\n";    
    # and exit
    exit $NeuroDB::ExitCodes::INSERT_FAILURE;
}

# Insert into files_intermediary the intermediary inputs stored in inputFileIDs.
my $intermediary_insert = &insert_intermedFiles($fileID, $inputFileIDs, $tool);
print LOG "\n==> FAILED TO INSERT INTERMEDIARY FILES FOR $fileID!\n\n" if (!$intermediary_insert);

my $horizontalPics = &NeuroDB::DBI::getConfigSetting(
                        \$dbh,'horizontalPics'
                        );
if  ($file->getFileDatum('FileType') eq 'mnc')  {
    # Jivify
    print LOG "Making JIV\n";
    &NeuroDB::MRI::make_jiv(\$file, $data_dir, $jiv_dir);
    
    # make the browser pics
    print "Making browser pics\n";
    &NeuroDB::MRI::make_pics(\$file, $data_dir, $pic_dir, $horizontalPics, $db);
}

# tell the user we've done so and include the MRIID for reference
print LOG "\n ==> Registered $filename in database, given FileID: $fileID\n\n";

# and exit
$dbh->disconnect;
exit $NeuroDB::ExitCodes::SUCCESS;


###################################
##           Functions           ##
###################################
=pod
This function returns the sessionID based on sourceFileID.
=cut
sub getSessionID    {
    my  ($sourceFileID,$dbh)    =   @_;
    
    # get sessionID using sourceFileID
    my  ($sessionID, %subjectIDsref);
    my  $query  =   "SELECT f.SessionID, " .
                           "s.CandID, " .
                           "s.Visit_label " .
                    "FROM files f " .
                    "JOIN session s ON (s.ID=f.SessionID) " .
                    "WHERE FileID=?";

    my  $sth    =   $dbh->prepare($query);
    $sth->execute($sourceFileID);

    if  ($sth->rows > 0) {
        my $row                         =   $sth->fetchrow_hashref();
        $sessionID                      =   $row->{'SessionID'};
        $subjectIDsref{'CandID'}        =   $row->{'CandID'};
        $subjectIDsref{'visitLabel'}    =   $row->{'Visit_label'};
    }else{
        return undef;
    }

    # set requiresStaging to null as long as don't have any more information on this field
    my $requiresStaging =   0;

    return  ($sessionID,$requiresStaging,\%subjectIDsref);
}


=pod
This function gets ScannerID from files using sourceFileID
=cut
sub getScannerID    {
    my  ($sourceFileID,$dbh)    =   @_;    

    my $scannerID;
    my $query   =   "SELECT f.ScannerID AS ScannerID " .
                    "FROM files AS f " .
                    "WHERE f.FileID=?";
    my $sth     =   $dbh->prepare($query);
    $sth->execute($sourceFileID);
    if($sth->rows > 0) {
        my $row     =   $sth->fetchrow_hashref();
        $scannerID  =   $row->{'ScannerID'};
    }else{
        return  undef;
    }

    return  ($scannerID);
}

=pod
This function returns the AcquisitionProtocolID of the file to register in DB based on scanType in mri_scan_type.
=cut
sub getAcqProtID    {
    my  ($scanType,$dbh)    =   @_;

    my  $acqProtID;
    my  $query  =   "SELECT ID " .
                    "FROM mri_scan_type " .
                    "WHERE Scan_type=?";
    my  $sth    =   $dbh->prepare($query);
    $sth->execute($scanType);
    if($sth->rows > 0) {
        my $row     =   $sth->fetchrow_hashref();
        $acqProtID  =   $row->{'ID'};
    }else{
        return  undef;
    }

    return  ($acqProtID);
}

=pod
This function parses the mincheader and look for specific field's value.
=cut
sub fetchMincHeader {
    my  ($file,$field)  =   @_;

    my  $value  =   `mincheader $file | grep '$field' | awk '{print \$3, \$4, \$5, \$6}' | tr '\n' ' '`;

    $value=~s/"//g;    #remove "
    $value=~s/^\s+//; #remove leading spaces
    $value=~s/\s+$//; #remove trailing spaces
    $value=~s/;//;    #remove ;

    return  $value;
}    

=pod
Move files to assembly folder.
=cut
sub copy_file {
    my ($filename, $subjectIDsref, $scan_type, $fileref)    =   @_;

    my ($new_name, $version);
    my $basename    =   &getSourceFilename($$fileref->{'fileData'}{'SourceFileID'});

    # figure out where to put the files
    my $dir         =   &which_directory($subjectIDsref);
    `mkdir -p -m 770 $dir/processed/$sourcePipeline`;

    # figure out what to call files
    my @exts        =   split(/\./, basename($$filename));
    shift @exts;
    my $extension   =   join('.', @exts);

    my $concat  =   "";
    $concat     =   '_concat' if $filename =~ /_concat/;

    my $new_dir =   "$dir/processed/$sourcePipeline";

    $version    =   1;
    $new_name   =   $basename . "_" . $scan_type . "_" . sprintf("%03d",$version) . $concat . ".$extension";
    $new_name   =~  s/ //;
    $new_name   =~  s/__+/_/g;

    while   (-e "$new_dir/$new_name") {
        $version    =   $version + 1;
        $new_name   =   $basename . "_" . $scan_type . "_" . sprintf("%03d",$version) . $concat . ".$extension";
        $new_name   =~  s/ //;
        $new_name   =~  s/__+/_/g;
    }

    $new_name   =   "$new_dir/$new_name";

    my $cmd     =   "cp $$filename $new_name";
    system($cmd);
    
    print LOG "File $$filename \n moved to:\n $new_name\n";
    $$filename  =   $new_name;

    return ($new_name);
}



=pod
Grep source file name from the database using SourceFileID.
Input:  $sourceFileID
Output: $filename
=cut
sub getSourceFilename {
    my ($sourceFileID) = @_;

    my $query   = "SELECT File " .
                  "FROM files "  .
                  "WHERE FileID=?";
    my $sth     = $dbh->prepare($query);
    $sth->execute($sourceFileID);

    my $filename;
    if($sth->rows > 0) {
        my $row     =   $sth->fetchrow_hashref();
        $filename   =   $row->{'File'};
    }else{
        return  undef;
    }

    my $basename    = basename($filename);
    $basename       =~ s/\.mnc$//i;

    return ($basename);
}



=pod
Determines where the mincs will go...
=cut
sub which_directory {
    my ($subjectIDsref) =   @_;
    
    my %subjectIDs  =   %$subjectIDsref;
    my $dir         =   $data_dir;

    $dir    =   "$dir/assembly/$subjectIDs{'CandID'}/$subjectIDs{'visitLabel'}/mri";
    $dir    =~  s/ //;
    
    return ($dir);
}


=pod
Function that will insert into the files_intermediary table of the database, intermediary outputs that were used to obtain the processed file.
- Input:  - fileID : fileID of the registered processed file
          - inputFileIDs : array containing the list of input files that were used to obtain the processed file
          - tool : tool that was used to obtain the processed file
- Output: - return undef if insertion did not succeed
          - return 1 if insertion into the intermediary table succeeded. 
=cut
sub insert_intermedFiles {
    my ($fileID, $inputFileIDs, $tool) = @_;

    return undef if ((!$fileID) || (!$inputFileIDs) || (!$tool));

    # Prepare query to execute in the for loop 
    my $query   = "INSERT INTO files_intermediary " .
                  "(Output_FileID, Input_FileID, Tool) " .
                  "Values (?, ?, ?)";
    my $sth     = $dbh->prepare($query);

    my (@inputIDs)  = split(';', $inputFileIDs);
    foreach my $inID (@inputIDs) {
        my $success = $sth->execute($fileID, $inID, $tool);
        return undef if (!$success);
    }

    return 1;
}

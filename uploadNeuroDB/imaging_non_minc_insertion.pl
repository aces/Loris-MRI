#! /usr/bin/perl

=pod

=head1 NAME

imaging_non_minc_insertion.pl -- Insert a non-MINC imaging file into the files table

=head1 SYNOPSIS

perl imaging_non_minc_insertion.pl C<[options]>

Available options are:

-profile       : name of the config file in C<../dicom-archive/.loris-mri> (required)

-file_path     : file to register into the database (full path from the root
                 directory is required) (required)

-upload_id     : ID of the uploaded imaging archive containing the file given as
                 argument with C<-file_path> option (required)

-output_type   : file's output type (e.g. native, qc, processed...) (required)

-scan_type     : file's scan type (from the C<mri_scan_type> table) (required)

-date_acquired : acquisition date for the file (C<YYYY-MM-DD>) (required)

-scanner_id    : ID of the scanner stored in the mri_scanner table (required)

-coordin_space : coordinate space of the file to register (e.g. native, linear,
                 nonlinear, nativeT1) (required)

-reckless      : upload data to the database even if the study protocol
                 is not defined or if it is violated

-verbose       : boolean, if set, run the script in verbose mode

-patient_name  : patient name, if cannot be found in the file name (in the form of
                 C<PSCID_CandID_VisitLabel>) (optional)

-metadata_file : file that can be read to look for metadata information to attach
                 to the file to be inserted (optional)

=head1 DESCRIPTION

This script inserts a file in the files and parameter_file tables. Optionally, a
metadata JSON file can be provided and that metadata will be stored in the
parameter_file table.

An example of a JSON metadata file would be:
{
  "tr": 2000,
  "te": 30,
  "slice_thickness": 2
}

Note that in order to be able to insert a scan with this script, you need to
provide the following information:
- path to the file
- upload ID associated to that file
- output type of that file (native, qc, processed...)
- the scan type of the file (from mri_scan_type)
- the acquisition date of the file
- the scanner ID this file was acquired with
- the coordinate space of the file (native, linear, nonlinear, nativeT1...)

=head2 Methods

=cut

use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use File::Temp qw/ tempdir /;
use Date::Parse;
use JSON;

###### Import NeuroDB libraries to be used
use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::File;
use NeuroDB::MRIProcessingUtility;
use NeuroDB::ExitCodes;


###### Table-driven argument parsing

# Initialize variables for Getopt::Tabular
my $profile;
my $file_path;
my $upload_id;
my $patient_name;
my $output_type;
my $scan_type;
my $date_acquired;
my $scanner_id;
my $coordin_space;
my $metadata_file;
my $verbose  = 0;
my $reckless = 0;   # only for playing & testing. Don't set it to 1!!!
my @args;

# Describe the usage to be displayed by Getopt::Tabular
my  $Usage  =   <<USAGE;

This script inserts a file in the files and parameter_file tables.

Usage: perl imaging_non_minc_insertion.pl [options]

-help for options

USAGE

# Set the variable descriptions to be used by Getopt::Tabular
my $profile_desc       = "name of config file in ./dicom-archive/.loris_mri.";
my $file_path_desc     = "file to register into the database (full path from "
                         . "the root directory is required)";
my $upload_id_desc     = "ID of the uploaded imaging archive containing the "
                         . "file given as argument with -file_path option";
my $pname_desc         = "patient name, if cannot be found in the file name "
                         . "(in the form of PSCID_CandID_VisitLabel)";
my $output_type_desc   = "file's output type (e.g. native, qc, processed...)";
my $scan_type_desc     = "file's scan type (from the mri_scan_type table)";
my $date_acquired_desc = "acquisition date for the file (YYYY-MM-DD)";
my $scanner_id_desc    = "ID of the scanner stored in the mri_scanner table";
my $coordin_space_desc = "Coordinate space of the file to register (e.g. "
                         . "native, linear, nonlinear, nativeT1)";
my $reckless_desc      = "upload data to database even if study protocol is "
                         . "not defined or violated.";
my $metadata_file_desc = "file that can be read to look for metadata "
                         . "information to attach to the file to be inserted";


# Initialize the arguments table
my @args_table = (

    ["Mandatory options", "section"],

        ["-profile",       "string",  1, \$profile,       $profile_desc      ],
        ["-file_path",     "string",  1, \$file_path,     $file_path_desc    ],
        ["-upload_id",     "string",  1, \$upload_id,     $upload_id_desc    ],
        ["-output_type",   "string",  1, \$output_type,   $output_type_desc  ],
        ["-scan_type",     "string",  1, \$scan_type,     $scan_type_desc    ],
        ["-date_acquired", "string",  1, \$date_acquired, $date_acquired_desc],
        ["-scanner_id",    "string",  1, \$scanner_id,    $scanner_id_desc   ],
        ["-coordin_space", "string",  1, \$coordin_space, $coordin_space_desc],

    ["Advanced options", "section"],

        ["-reckless",    "boolean", 1, \$reckless,    $reckless_desc ],
        ["-verbose",     "boolean", 1, \$verbose,     "Be verbose"   ],

    ["Optional options", "section"],
        ["-patient_name",  "string", 1, \$patient_name,  $pname_desc        ],
        ["-metadata_file", "string", 1, \$metadata_file, $metadata_file_desc]

);

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

# Input option error checking
if  ( !$profile ) {
    print STDERR "$Usage\n\tERROR: You must specify a profile.\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if  ( !@Settings::db )    {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}

# Ensure that all the arguments that we need are set
unless ( $file_path ) {
    print STDERR "$Usage\n\tERROR: missing -file_path argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
unless ( $output_type ) {
    print STDERR "$Usage\n\tERROR: missing -output_type argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
unless ( $scan_type ) {
    print STDERR "$Usage\n\tERROR: missing -scan_type argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
unless ( $date_acquired ) {
    print STDERR "$Usage\n\tERROR: missing -date_acquired argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
unless ( $scanner_id ) {
    print STDERR "$Usage\n\tERROR: missing -scanner_id argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
unless ( $coordin_space ) {
    print STDERR "$Usage\n\tERROR: missing -coordin_space argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
unless ( $upload_id ) {
    print STDERR "$Usage\n\tERROR: missing -upload_id argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}

# Ensure the files specified as an argument exist and are readable
unless (-r $file_path) {
    print STDERR "$Usage\n\tERROR: You must specify a valid file path to "
                 . "insert using the -file_path option.\n\n";
    exit $NeuroDB::ExitCodes::INVALID_PATH;
}
# Ensure that the metadata file is readable if it is set
if ( $metadata_file && !(-r $metadata_file) ){
    print STDERR "\n\tERROR: The metadata file does not exist in the filesystem.\n\n";
    exit $NeuroDB::ExitCodes::INVALID_PATH;
}




###### Establish database connection

my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);




###### Get config settings

my $data_dir = NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath');




###### For the log, temp directories and notification spools

# determine local time
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $today = sprintf( "%4d-%02d-%02d %02d:%02d:%02d",
                     $year+1900,$mon+1,$mday,$hour,$min,$sec
);

# create the temp directory
my $template = "FileLoad-$hour-$min-XXXXXX";
my $TmpDir   = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
my @temp     = split(/\//, $TmpDir);
my $temp_log = $temp[$#temp];

# create the log file
my $log_dir  = $data_dir . "/logs";
my $log_file = $log_dir . "/" . $temp_log . ".log";
my $message  = "\nlog dir is $log_dir and log file is $log_file.\n";
print $message if $verbose;

# open log file and write successful connection to DB
open( LOG, ">>", $log_file ) or die "\nError Opening $log_file.\n";
LOG->autoflush(1);
&logHeader();
$message = "\n==> Successfully connected to database\n";
print LOG $message;

# create Notify and Utility objects
my $notifier = NeuroDB::Notify->new(\$dbh);
my $utility = NeuroDB::MRIProcessingUtility->new(
    \$dbh, 0, $TmpDir, $log_file, $verbose
);




##### Exit if the provided scanner ID does not refer to a valid scanner entry
unless ( defined NeuroDB::MRI::getScannerCandID($scanner_id, \$dbh) ) {
    # if no row returned, exits with message that did not find this scanner ID
    $message = "\n\tERROR: Invalid ScannerID $scanner_id.\n\n";
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::SELECT_FAILURE, $log_file
    );
    # insert error message into notification spool table
    $notifier->spool(
        'imaging non minc file insertion'   , $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::SELECT_FAILURE;
}




##### Verify that the upload ID refers to a valid upload ID
my $query = "SELECT UploadID FROM mri_upload WHERE UploadID=?";
my $sth = $dbh->prepare($query);
$sth->execute($upload_id);
unless ($sth->rows > 0) {
    # if no row returned, exits with message that did not find this upload ID
    $message = "\n\tERROR: Invalid UploadID $upload_id.\n\n";
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::SELECT_FAILURE, $log_file
    );
    # insert error message into notification spool table
    $notifier->spool(
        'imaging non minc file insertion'   , $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::SELECT_FAILURE;
}




###### Determine the acquisition protocol ID of the file based on scan type

# verify that an acquisition protocol ID exists for $scan_type
my $acqProtocolID = NeuroDB::MRI::scan_type_text_to_id($scan_type, \$dbh);
if ($acqProtocolID =~ /unknown/){
    $message = "\n\tERROR: no AcquisitionProtocolID found for $scan_type.\n\n";
    # write error message in the log file
    $utility->writeErrorLog( $message, $NeuroDB::ExitCodes::UNKNOWN_PROTOCOL, $log_file );
    # insert error message into notification spool table
    $notifier->spool(
        'imaging non minc file insertion',    $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::UNKNOWN_PROTOCOL;
} else {
    $message = "\nFound protocol ID $acqProtocolID for $scan_type.\n\n";
    $notifier->spool(
        'imaging non minc file insertion',    $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'Y'
    )
}




###### Create and Load File object

# create File object
my $file = NeuroDB::File->new(\$dbh);

# file type determined here as long as the it exists in ImagingFileTypes table
$file->loadFileFromDisk($file_path);




###### Determine file basename and directory name

# Get the file name and directory name of $file_path
my ($file_name, $dir_name) = fileparse($file_path);




###### Determine the metadata to be stored in parameter_file if a JSON metadata
###### file is provided

if ($metadata_file) {
    # read the JSON file into $json
    local $/;  # Enable 'slurp' mode
    open( FILE, $metadata_file ) or die "Could not open file: $!";
    my $json = <FILE>;
    close( FILE );

    my $metadata = decode_json($json);
    foreach my $parameter (sort keys $metadata) {
        $file->setParameter( $parameter, $metadata->{$parameter} );
    }
}




###### Determine candidate information

# create a hash similar to tarchiveInfo so that can use Utility routines to
# determine the candidate information
# if patient name provided as an argument, use it to get candidate/site info
# otherwise, use the file's name to determine candidate & site information
my %info = (
    SourceLocation => undef,
    PatientName    => ($patient_name // $file_name),
    PatientID      => ($patient_name // $file_name)
);

# determine subject ID information
my $subjectIDsref = $utility->determineSubjectID($scanner_id, \%info, 0);
unless (%$subjectIDsref){
    # exits if could not determine subject IDs
    $message = "\n\tERROR: could not determine subject IDs for $file_path.\n\n";
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::GET_SUBJECT_ID_FAILURE, $log_file
    );
    # insert error message into notification spool table
    $notifier->spool(
        'imaging non minc file insertion'   , $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::GET_SUBJECT_ID_FAILURE;
}

# check whether there is a candidate IDs mismatch error
my $CandMismatchError;
$CandMismatchError = $utility->validateCandidate($subjectIDsref);
if ($CandMismatchError){
    # exits if there is a mismatch in candidate IDs
    $message = "\n\tERROR: Candidate IDs mismatch for $file_path.\n\n";
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::CANDIDATE_MISMATCH, $log_file
    );
    # insert error message into notification spool table
    $notifier->spool(
        'imaging non minc file insertion'   , $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::CANDIDATE_MISMATCH;
} else {
    $message = "Validation of candidate information has passed.\n\n";
    $notifier->spool(
        'imaging non minc file insertion',    $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'N'
    )
}

# determine the session ID
my ($session_id, $requiresStaging) = NeuroDB::MRI::getSessionID(
    $subjectIDsref, $date_acquired, \$dbh, $subjectIDsref->{'subprojectID'}
);
unless ($session_id) {
    $message = "\n\tERROR: Could not determine session ID for $file_path.\n\n";
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::GET_SESSION_ID_FAILURE, $log_file
    );
    # insert error message into notification spool table
    $notifier->spool(
        'imaging non minc file insertion'   , $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::GET_SESSION_ID_FAILURE;
}





###### Compute the md5hash and check if file is unique

my $unique = $utility->computeMd5Hash($file, $info{'SourceLocation'});
if (!$unique) {
    $message = "\n\tERROR: This file has already been uploaded!\n\n";
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::FILE_NOT_UNIQUE, $log_file
    );
    # insert error message into notification spool table
    $notifier->spool(
        'imaging non minc file insertion'   , $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::FILE_NOT_UNIQUE;
}




#### Set File data

# message to write in the LOG file
$message = <<MESSAGE;
    -> ScannerID was set to $scanner_id\n
    -> SessionID was set to $session_id\n
    -> Acquisition date was set to $date_acquired\n
    -> Output type was set to $output_type\n\n
MESSAGE
print $message if $verbose;
print LOG $message;

$notifier->spool(
    'imaging non minc file insertion',    $message,   0,
    'imaging_non_minc_insertion.pl', $upload_id, 'Y',
    'Y'
);

# set file's scanner ID to $scanner_id
$file->setFileData( 'ScannerID', $scanner_id );

# set session ID to $sessionID
$file->setFileData( 'SessionID', $session_id );

# set acquisition date
my ($ss, $mm, $hh, $day, $month, $yy, $zone) = strptime( $date_acquired );
$date_acquired = sprintf( "%4d-%02d-%02d", $yy+1900, $month+1, $day );
$file->setParameter( 'AcquisitionDate', $date_acquired );

# set output type
$file->setFileData( 'OutputType', $output_type );




###### Register scan into DB

# note, have to give an array of checks, for now, hardcoding it to 'pass'
# until we end up with a case where this should not be the case.
my $acquisitionProtocolIDFromProd = $utility->registerScanIntoDB(
    \$file,     undef,    $subjectIDsref, $scan_type,
    $file_path, ['pass'], $reckless,      $session_id,
    $upload_id
);
if ( $acquisitionProtocolIDFromProd ) {
    my $registered_file = $file->getFileDatum('File');
    $message = "Registered file $registered_file successfully.\n\n";
    $notifier->spool(
        'imaging non minc file insertion',    $message,   0,
        'imaging_non_minc_insertion.pl', $upload_id, 'Y',
        'N'
    );
}




exit $NeuroDB::ExitCodes::SUCCESS;


=pod

=head3 logHeader()

Prints the log file's header with time of insertion and temp directory location.

=cut

sub logHeader () {

    print LOG "
----------------------------------------------------------------
            AUTOMATED FILE INSERTION
----------------------------------------------------------------
*** Date and time of insertion : $today
*** tmp dir location           : $TmpDir
";

}


=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut


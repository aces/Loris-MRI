
# Generic TODOs:

##TODO 1: once ExitCodes.pm class merged, replace exit codes by the variables
# from that class


use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use File::Temp qw/ tempdir /;
use Date::Parse;

###### Import NeuroDB libraries to be used
use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::File;
use NeuroDB::MRIProcessingUtility;
##TODO 1: add line use NeuroDB::ExitCodes;



###### Table-driven argument parsing

# Initialize variables for Getopt::Tabular
my $profile       = undef;
my $file_path     = undef;
my $patient_name  = undef;
my $output_type   = undef;
my $scan_type     = undef;
my $date_acquired = undef;
my $scanner_id    = undef;
my $coordin_space = undef;
my $metadata_file = undef;
my $verbose       = 0;
my $reckless      = 0;   # only for playing & testing. Don't set it to 1!!!
my @args;

# Describe the usage to be displayed by Getopt::Tabular
my  $Usage  =   <<USAGE;

This script inserts a file in the files and parameter_file tables.

Usage: perl file_insertion.pl [options]

-help for options

USAGE

# Set the variable descriptions to be used by Getopt::Tabular
my $profile_desc       = "name of config file in ./dicom-archive/.loris_mri.";
my $file_path_desc     = "file to register into the database (full path from "
                         . "the root directory is required)";
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
##TODO 1: replace exit 1 by $NeuroDB::ExitCodes::GETOPT_FAILURE
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# Input option error checking
if  (!$profile) {
    print "$Usage\n\tERROR: You must specify a profile.\n\n";
    ##TODO 1: replace exit 2 by $NeuroDB::ExitCodes::PROFILE_FAILURE
    exit 2;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if  ($profile && !@Settings::db)    {
    print "\n\tERROR: You don't have a @db setting in the file "
          . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    ##TODO 1: replace exit 4 by $NeuroDB::ExitCodes::DB_SETTING_FAILURE
    exit 4;
}

# Make sure that all the arguments that we need are set
unless ( $file_path ) {
    print "$Usage\n\tERROR: missing -file_path argument\n\n";
    ##TODO 1: replace exit 3 by $NeuroDB::ExitCodes::MISSING_ARG
    exit 3;
}
unless ( $output_type ) {
    print "$Usage\n\tERROR: missing -output_type argument\n\n";
    ##TODO 1: replace exit 3 by $NeuroDB::ExitCodes::MISSING_ARG
    exit 3;
}
unless ( $scan_type ) {
    print "$Usage\n\tERROR: missing -scan_type argument\n\n";
    ##TODO 1: replace exit 3 by $NeuroDB::ExitCodes::MISSING_ARG
    exit 3;
}
unless ( $date_acquired ) {
    print "$Usage\n\tERROR: missing -date_acquired argument\n\n";
    ##TODO 1: replace exit 3 by $NeuroDB::ExitCodes::MISSING_ARG
    exit 3;
}
unless ( $scanner_id ) {
    print "$Usage\n\tERROR: missing -scanner_ID argument\n\n";
    ##TODO 1: replace exit 3 by $NeuroDB::ExitCodes::MISSING_ARG
    exit 3;
}
unless ( $coordin_space ) {
    print "$Usage\n\tERROR: missing -coordin_space argument\n\n";
    ##TODO 1: replace exit 3 by $NeuroDB::ExitCodes::MISSING_ARG
    exit 3;
}

# Make sure the files specified as an argument exist and are readable
unless (-r $file_path) {
    print "$Usage\n\tERROR: You must specify a valid file path to insert "
          . "using the -file_path option.\n\n";
    ##TODO 1: replace exit 5 by $NeuroDB::ExitCodes::ARG_FILE_DOES_NOT_EXIST
    exit 5;
}
# Make sure that the metadata file is readable if it is set
if ( $metadata_file && !(-r $metadata_file) ){
    print "\n\tERROR: The metadata file does not exist in the filesystem.\n\n";
    ##TODO 1: replace exit 5 by $NeuroDB::ExitCodes::ARG_FILE_DOES_NOT_EXIST
    exit 5;
}





###### Establish database connection

my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);




###### Get config settings

my $data_dir = NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath');




###### For the log and temp directories

# determine local time
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

# temp directory
my $template = "FileLoad-$hour-$min-XXXXXX";
my $TmpDir   = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
my @temp     = split(/\//, $TmpDir);
my $temp_log = $temp[$#temp];

# log
my $log_dir  = $data_dir . "/logs";
my $logfile  = $log_dir . "/" . $temp_log . ".log";
my $message  = "";




###### Create File, Utility and Notify objects

# Create File object
my $file = NeuroDB::File->new(\$dbh);

# Create Utility object
my $utility = NeuroDB::MRIProcessingUtility->new(
    \$dbh, 0, $TmpDir, $logfile, $verbose
);

# Load Notify object
my $notifier = NeuroDB::Notify->new(\$dbh);




###### Load File object

# Load File object (file type will be automatically determined here as long
# as the file type exists in the ImagingFileTypes table)
$file->loadFileFromDisk($file_path);




###### Determine file basename and directory name

# Get the file name and directory name of $file_path
my ($file_name, $dir_name) = fileparse($file_path);




###### Determine the metadata to be stored in parameter_file

##TODO: read a simply ASCII or JSON file to grep the metadata (would be
# created by the overall insertion scripts like PET_loader etc...)




###### Determine candidate information

# create a hash similar to tarchiveInfo so that can use Utility routines to
# determine the candidate information
my %info;

# for now, set SourceLocation to undef
$info{'SourceLocation'} = undef;

if ($patient_name) {
    # if the patient name has been provided as an argument to the script, then
    # use it to determine candidate & site information
    $info{'PatientName'} = $patient_name;
    $info{'PatientID'}   = $patient_name;
} else {
    # otherwise, use the file's name to determine candidate & site information
    $info{'PatientName'} = $file_name;
    $info{'PatientID'}   = $file_name;
}

# determine subject ID information
my $subjectIDsref = $utility->determineSubjectID($scanner_id, \%info, 0);
##TODO: proper logging
##TODO 1: create an exit code in ExitCodes.pm and call it here
exit unless ($subjectIDsref);

# candidate IDs mismatch error
my $CandMismatchError = undef;
$CandMismatchError = $utility->validateCandidate(
                        $subjectIDsref, $info{'SourceLocation'}
);
##TODO: proper logging
##TODO 1: create an exit code in ExitCodes.pm and call it here
exit if ($CandMismatchError); # exits if there is a mismatch in candidate IDs

# determine sessionID
my ($sessionID, $requiresStaging) = NeuroDB::MRI::getSessionID(
                                        $subjectIDsref,
                                        $date_acquired,
                                        \$dbh,
                                        $subjectIDsref->{'subprojectID'}
);
$file->setFileData('SessionID', $sessionID);
print "\t -> Set SessionID to $sessionID.\n";




#### Set the scanner ID if it exists in the database
(my $query = <<QUERY) =~ s/\n/ /gm;
SELECT ID FROM mri_scanner WHERE ID=?
QUERY
my $sth = $dbh->prepare($query);
$sth->execute();

unless ($sth->rows > 0) {
    # if no row returned, exits with message that the scanner ID provided
    # does not exist
    print "\nERROR: did not find any scanner with ID=$scanner_id.\n\n";
    ##TODO: proper logging
    ##TODO 1: create an exit code in ExitCodes.pm and call it here
    exit;
}
# set file's scanner ID to $scanner_id
$file->setFileData('ScannerID', $scanner_id);
print "\t -> Set ScannerID to $scanner_id.\n";




###### Determine the acquisition protocol ID of the file based on scan type

# verify that an acquisition protocol ID exists for $scan_type
my $acqProtocolID = NeuroDB::MRI::scan_type_text_to_id($scan_type, \$dbh);
if ($acqProtocolID =~ /unknown/){
    print "\tERROR: no acquisition protocol ID found for $scan_type.\n\n";
    ##TODO: proper logging
    ##TODO 1: create an exit code in ExitCodes.pm and call it here
    exit;
}




###### Set the acquisition date

my ($ss, $mm, $hh, $day, $month, $year, $zone) = strptime($date_acquired);
$date_acquired = sprintf("%4d-%02d-%02d",$year+1900,$month+1,$day);
$file->setParameter('AcquisitionDate', $date_acquired);




###### Determine the output type (native, qc, processed...)

$file->setFileData('OutputType', $output_type);
print "\t -> Set OutputType to $output_type.\n";
##TODO: proper logging



###### Compute the md5hash and check if file is unique

my $unique = $utility->computeMd5Hash($file, $info{'SourceLocation'});
if (!$unique) {
    $message = "\n--> WARNING: This file has already been uploaded!\n";
    print $message if $verbose;
#    print LOG $message;
#    $notifier->spool('tarchive validation', $message, 0,
#        'minc_insertion.pl', $upload_id, 'Y',
#        $notify_notsummary);
    #TODO: proper logging
    ##TODO 1: replace exit 8 by $NeuroDB::ExitCodes::$FILE_NOT_UNIQUE
    exit 8;
}




###### Register scan into DB

# note, have to give an array of checks, for now, hardcoding it to 'pass'
# until we end up with a case where this should not be the case.
my $acquisitionProtocolIDFromProd = $utility->registerScanIntoDB(
    \$file,     undef,    $subjectIDsref, $scan_type,
    $file_path, ['pass'], $reckless,      undef,
    $sessionID
);

##TODO 1: replace exit 0 by $NeuroDB::ExitCodes::$SUCCESS
exit 0;

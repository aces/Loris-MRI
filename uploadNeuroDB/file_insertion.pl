use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use File::Temp qw/ tempdir /;

###### Import NeuroDB libraries to be used
use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::File;
use NeuroDB::MRIProcessingUtility;


#
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);



###### Table-driven argument parsing

# Initialize variables for Getopt::Tabular
my $profile       = undef;
my $file_path     = undef;
my $patient_name  = undef;
my $output_type   = undef;
my $scan_type     = undef;
my $date_acquired = undef;
my $scanner_id    = undef;
my $verbose       = 0;
my $reckless      = 0;   # only for playing & testing. Don't set it to 1!!!
my $new_scanner   = 1;   # 1 should be the default unless you're a control freak
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
my $pname_desc         = "patient name (in the form of "
                         . "PSCID_CandID_VisitLabel)";
my $output_type_desc   = "file's output type (e.g. native, qc, processed...)";
my $scan_type_desc     = "file's scan type (from the mri_scan_type table)";
my $date_acquired_desc = "acquisition date for the file";
my $scanner_id_desc    = "ID of the scanner stored in the mri_scanner table";
my $reckless_desc      = "Upload data to database even if study protocol is "
                         . "not defined or violated.";
my $new_scanner_desc   = "By default a new scanner will be registered if the "
                         . "data you upload requires it. You can risk "
                         . "turning it off.";

# Initialize the arguments table
my @args_table = (

    ["Basic options", "section"],

        ["-profile",   "string",  1, \$profile,   $profile_desc],
        ["-file_path", "string",  1, \$file_path, $file_path_desc],
        ["-verbose",   "boolean", 1, \$verbose,   "Be verbose"],

    ["Advanced options", "section"],

        ["-reckless",    "boolean", 1, \$reckless,    $reckless_desc],
        ["-new_scanner", "boolean", 1, \$new_scanner, $new_scanner_desc],

    ["Optional options", "section"],

        ["-patient_name",  "string", 1, \$patient_name,  $pname_desc],
        ["-output_type",   "string", 1, \$output_type,   $output_type_desc],
        ["-scan_type",     "string", 1, \$scan_type,     $scan_type_desc],
        ["-date_acquired", "string", 1, \$date_acquired, $date_acquired_desc],
        ["-scanner_id",    "string", 1, \$scanner_id,    $scanner_id_desc]
);

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# Input option error checking
if  (!$profile) {
    print "$Usage\n\tERROR: You must specify a profile.\n\n";
    exit 33;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if  ($profile && !@Settings::db)    {
    print "\n\tERROR: You don't have a configuration file named "
          . "'$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit 33;
}

# Make sure we have all the arguments that we need set
unless (-e $file_path) {
    print "$Usage\n\tERROR: You must specify a valid file path to insert "
          . "using the -file_path option.\n\n";
    exit 33;
}
##TODO more can go there as the script gets more arguments




###### Establish database connection

my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);




###### Get config settings

my $data_dir = NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath');




###### For the log and temp directories

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
# as the file type exists in the ImagingFileTypes table
$file->loadFileFromDisk($file_path);




###### Determine file basename and directory name

# Get the file name and directory name of $file_path
my ($file_name, $dir_name) = fileparse($file_path);




###### Determine the metadata to be stored in parameter_file

##TODO: that's going to be a pickle!!




###### Determine center name and ID, scanner ID and candidate information

# create a hash similar to tarchiveInfo so that can use Utility routines to
# determine the center name, center ID, scanner ID and candidate information
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

# get the center name, center ID
my ($center_name, $center_id) = $utility->determinePSC(\%info, 0);



# determine the scanner ID
#TODO: have that specified at the command line or grep this from metadata
# $info{'ScannerManufacturer'}    = $scanner_manufacturer;
# $info{'ScannerModel'}           = $scanner_model;
# $info{'ScannerSerialNumber'}    = $scanner_serial_number;
# $info{'ScannerSoftwareVersion'} = $scanner_software_version,
# $scanner_id = $utility->determineScannerID(
#                    \%info, 0, $center_id, $new_scanner
#);

# determine subject ID information
my $subjectIDsref = $utility->determineSubjectID($scanner_id, \%info, 0);
##TODO exit with an exit code here if candidate was not found and log in DB
exit unless ($subjectIDsref);

# candidate IDs mismatch error
my $CandMismatchError = undef;
$CandMismatchError = $utility->validateCandidate(
                        $subjectIDsref, $info{'SourceLocation'}
);
##TODO exit with an exit code here if candidate IDs mismatch and log this in DB
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



###### Determine the scan type and acquisition protocol ID of the file

##TODO: depending on the type of the file load, could maybe determine this
# from metadata or filename? For now, just exits if scan type is not defined

unless ($scan_type) {
    print "\nERROR: could not determine the scan type of $file_path.\n\n";
    exit;
}

# determine acquisition protocol ID
my $acqProtocolID;
my @checks; #TODO: verify if can remove @checks as won't be used
($scan_type, $acqProtocolID, @checks) = $utility->getAcquisitionProtocol(
    $file, $subjectIDsref, \%info, $center_name, $file_path, $scan_type, 0
);




###### Determine the output type (native, qc, processed...)

if ($output_type) {
    # if the output type has been provided as an argument to the script, then
    # use its value in the OutputType field of the files table
    $file->setFileData('OutputType', $output_type);
    print "\t -> Set OutputType to $output_type.\n";
} else {
    # otherwise, use information somewhere from the file to determine it
    #TODO: we'll see when we get there... Might change depending if eeg, pet...
}




###### Determine the scanner ID
##TODO: might want to create new scanners if following arguments are passed:
# $manufacturer, $model, $serialNumber, $softwareVersion, $register_new, if
# so, would call function NeuroDB::MRI::findScannerID()

if ($scanner_id) {
    # if the scanner ID has been provided as an argument to the script, then
    # use its value in the ScannerID field of the files table (after having
    # checked that this scanner ID exists in the mri_scanner table)
    (my $query = <<QUERY) =~ s/\n/ /gm;
SELECT ID FROM mri_scanner WHERE ID=?
QUERY
    my $sth = $dbh->prepare($query);
    $sth->execute();


    if($sth->rows>0) {
        # if found scanner, set scanner ID to $scanner_id
        $file->setFileData('ScannerID', $scanner_id);
        print "\t -> Set ScannerID to $scanner_id.\n";
    } else {
        # otherwise, exits with message that the scanner ID provided does not
        #  exist
        print "\nERROR: did not find any scanner with ID=$scanner_id.\n\n";
        #TODO exit with code exit
        exit;
    }
} else {
    # otherwise, use information somewhere from the file to determine it or
    # set it to 0 if no way of finding that information
    ##TODO: we'll see when we get there... Might change depending on eeg, pet...
    $file->setFileData('ScannerID', 0);
}




###### Compute the md5hash and check if file is unique

my $unique = $utility->computeMd5Hash($file, $info{'SourceLocation'});
if (!$unique) {
    $message = "\n--> WARNING: This file has already been uploaded!\n";
    print $message if $verbose;
    print LOG $message;
#    $notifier->spool('tarchive validation', $message, 0,
#        'minc_insertion.pl', $upload_id, 'Y',
#        $notify_notsummary);
    exit 8;
}



###### Register scan into DB

my $acquisitionProtocolIDFromProd = $utility->registerScanIntoDB(
    \$file,     undef, $subjectIDsref, $scan_type,
    $file_path, undef, $reckless,      undef,
    $sessionID
);



##TODO: continue looking from step 7 of register processed data

exit 0;





=pod
This function returns the AcquisitionProtocolID of the file to register in DB
based on scanType in mri_scan_type.
=cut
##TODO move this function to one of the library file as it is the same as the
#  one used by register_processed_data.pl
sub getAcqProtID    {
    my  ($scanType, $dbh)    =   @_;

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

__END__



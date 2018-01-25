use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;

###### Import NeuroDB libraries to be used
use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::File;



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

# Initialize the arguments table
my @args_table = (

    ["Basic options", "section"],

        ["-profile",   "string",  1, \$profile,   $profile_desc],
        ["-file_path", "string",  1, \$file_path, $file_path_desc],
        ["-verbose",   "boolean", 1, \$verbose,   "Be verbose"],

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




###### Get the user that is performing the insert

my $InsertedByUserID = `whoami`;





###### Create and load File object.
# Create File object
my $file = NeuroDB::File->new(\$dbh);

# Load File object (file type will be automatically determined here as long
# as the file type exists in the ImagingFileTypes table
$file->loadFileFromDisk($file_path);




###### Determine file basename and directory name

# Get the file name and directory name of $file_path
##TODO: remove if not needed in the script later on
my ($file_name, $dir_name) = fileparse($file_path);
print "\nfile name: "   . $file_name
      . "\ndir name: "  . $dir_name;



###### Determine the candidate's IDs and SessionID

# determine subjectIDs
##TODO: investigate further if we can use determineSubjectID in
# MRIProcessingUtility. Difficult because of the hardcoded reference to
# TarchiveSourceLocation...
if (!defined(&Settings::getSubjectIDs)) {
    print "\nERROR: $profile does not contain getSubjectIDs() routine.\n\n";
}
my $subjectIDsref = undef;
if ($patient_name) {
    # if the patient name has been provided as an argument to the script, then
    # use it to determine Candidate's information
    $subjectIDsref = Settings::getSubjectIDs(
        $patient_name,
        $patient_name,
        undef,
        \$dbh
    );
} else {
    # otherwise, use the file's name to determine Candidate's information
    $subjectIDsref = Settings::getSubjectIDs(
        $file_name,
        $file_name,
        undef,
        \$dbh
    );
}
##TODO exit with an exit code here if candidate was not found
exit unless ($subjectIDsref);

# determine sessionID
my ($sessionID, $requiresStaging) = NeuroDB::MRI::getSessionID(
                                        $subjectIDsref,
                                        $date_acquired,
                                        \$dbh,
                                        $subjectIDsref->{'subprojectID'}
);
$file->setFileData('SessionID', $sessionID);
print "\t -> Set SessionID to $sessionID.\n";




###### Determine the metadata to be stored in parameter_file along with the file

##TODO: that's going to be a pickle!!




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




###### Determine the acquisition protocol ID

if ($scan_type) {
    # if the scan type has been provided as an argument to the script, then
    # use it to determine the acquisition protocol ID from mri_scan_type table
    my $acqProtID = getAcqProtID($scan_type, $dbh);
    if (!defined($acqProtID)) {
        print "\nERROR: could not determine AcquisitionProtocolID based "
              . "on scanType $scan_type.\n\n";
        exit 2;
    }
    $file->setFileData('AcquisitionProtocolID', $acqProtID);
    print "\t -> Set AcquisitionProtocolID to $acqProtID.\n";
} else {
    # otherwise, use information somewhere from the file to determine it
    ##TODO: we'll see when we get there... Might change depending if eeg, pet...
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
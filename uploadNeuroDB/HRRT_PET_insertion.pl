# Generic TODOs:

##TODO 1: once ExitCodes.pm class merged, replace exit codes by the variables
# from that class


use strict;
use warnings;
use Getopt::Tabular;
use File::Temp qw/ tempdir /;
use Date::Parse;


###### Import NeuroDB libraries to be used
use NeuroDB::DBI;
##TODO 1: add line use NeuroDB::ExitCodes;


##TODO 1: move those exit codes to ExitCodes.pm
my $INVALID_UPLOAD_ID = 150;

###### Table-driven argument parsing

# Initialize variables for Getopt::Tabular
my $profile   = undef;
my $upload_id = undef;
my $verbose   = 0;

# Describe the usage to be displayed by Getopt::Tabular
my  $Usage  =   <<USAGE;

This script takes an upload ID of a PET HRRT study to insert it into the
database with information about the list of files contained in the upload. It
will also grep the ecat7 files to convert them into MINC files and register
them into the files and parameter_file tables.

NOTE: in case the MINC files are already present in the PET HRRT study, it
will use the already created MINC instead of creating them.

Usage: perl HRRT_PET_insertion.pl [options]

-help for options

USAGE

# Set the variable descriptions to be used by Getopt::Tabular
my $profile_desc   = "name of config file in ./dicom-archive/.loris_mri.";
my $upload_id_desc = "ID of the uploaded imaging archive containing the "
                     . "file given as argument with -file_path option";

# Initialize the arguments table
my @args_table = (

    ["Mandatory options", "section"],

        ["-profile",   "string", 1, \$profile,   $profile_desc  ],
        ["-upload_id", "string", 1, \$upload_id, $upload_id_desc],

    ["Advanced options", "section"],

        ["-verbose",     "boolean", 1, \$verbose,     "Be verbose"   ],

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
    print "\n\tERROR: You don't have a \@db setting in the file "
        . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    ##TODO 1: replace exit 4 by $NeuroDB::ExitCodes::DB_SETTING_FAILURE
    exit 4;
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
my $template = "PetHrrtLoad-$hour-$min-XXXXXX";
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




##### Verify that the provided upload ID refers to a valid uploaded entry
(my $query = <<QUERY) =~ s/\n/ /gm;
SELECT UploadedLocation FROM mri_scanner WHERE UploadID=?
QUERY
my $sth = $dbh->prepare($query);
$sth->execute($upload_id);
unless ($sth->rows > 0) {
    # if no row returned, exits with message that did not find this scanner ID
    $message = <<MESSAGE;
    ERROR: Invalid UploadID $upload_id.\n\n
MESSAGE
    # write error message in the log file
    $utility->writeErrorLog( $message, $INVALID_UPLOAD_ID, $log_file );
    ##TODO 1: call the exit code from ExitCodes.pm
    # insert error message into notification spool table
    $notifier->spool(
        'HRRT_PET insertion'   , $message,   0,
        'HRRT_PET_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $INVALID_UPLOAD_ID; ##TODO 1: call the exit code from ExitCodes.pm
}
# Check that the uploadedlocation is valid
# check that PET not already inserted
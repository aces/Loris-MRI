# Generic TODOs:

##TODO 1: once ExitCodes.pm class merged, replace exit codes by the variables
# from that class


use strict;
use warnings;
use Getopt::Tabular;
use File::Temp qw/ tempdir /;
use Date::Parse;
use File::Basename;


###### Import NeuroDB libraries to be used
use NeuroDB::DBI;
use NeuroDB::Notify;
use NeuroDB::MRIProcessingUtility;
use NeuroDB::HRRT;
use NeuroDB::MincUtilities;
use NeuroDB::File;
##TODO 1: add line use NeuroDB::ExitCodes;


##TODO 1: move those exit codes to ExitCodes.pm
my $INVALID_UPLOAD_ID       = 150; # invalid upload ID
my $INVALID_UPLOAD_LOCATION = 151; # invalid upload location
my $INVALID_DECOMP_LOCATION = 152; # invalid decompressed location
my $HRRT_ARCHIVE_ALREADY_INSERTED = 153; # if HRRT archive already exists in DB
my $MINC_FILE_NOT_FOUND = 154; # if could not convert ECAT file into MINC

###### Table-driven argument parsing

# Initialize variables for Getopt::Tabular
my $profile;
my $upload_id;
my $verbose   = 0;
my $bic       = 0;
my @args;

# Describe the usage to be displayed by Getopt::Tabular
my  $Usage  =   <<USAGE;

This script takes an upload ID of a PET HRRT study to insert it into the
database with information about the list of files contained in the upload. It
will also grep the ecat7 files to insert their header information into the
database.

NOTE: in case the MINC files are already present in the PET HRRT study, it
will use the already created MINC instead of creating them.

Usage: perl HRRT_PET_archive.pl [options]

-help for options

USAGE

# Set the variable descriptions to be used by Getopt::Tabular
my $profile_desc   = "name of config file in ./dicom-archive/.loris_mri.";
my $upload_id_desc = "ID of the uploaded imaging archive containing the "
                     . "file given as argument with -file_path option";
my $bic_desc       = "whether the datasets comes from the BIC HRRT scanner";

# Initialize the arguments table
my @args_table = (

    ["Mandatory options", "section"],

        ["-profile",   "string", 1, \$profile,   $profile_desc  ],
        ["-upload_id", "string", 1, \$upload_id, $upload_id_desc],

    ["Advanced options", "section"],

        ["-verbose", "boolean", 1, \$verbose, "Be verbose"  ],

    ["Optional options", "section"],
        ["-bic_dataset", "boolean", 1, \$bic, $bic_desc]

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
my $utility  = NeuroDB::MRIProcessingUtility->new(
    \$dbh, 0, $TmpDir, $log_file, $verbose
);




##### Verify that the provided upload ID refers to a valid uploaded entry in
# the database and in the filesystem, and that it did not get already archived

# grep the UploadedLocation for the UploadID
my $upload_info = NeuroDB::DBI::getHrrtUploadInfo( $dbh, $upload_id );

# cheack that the upload ID was valid
unless ( $upload_info ) {

    # if no upload info, exits with message that did not find this upload ID
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

# check that decompressed location exists in the filesystem
unless ( -r $upload_info->{decompressed_location} ) {

    $message = <<MESSAGE;
    ERROR: The decompressedLocation $upload_info->{decompressed_location}
    cannot be found or read for UploadID $upload_id.\n\n
MESSAGE
    # write error message in the log file
    $utility->writeErrorLog($message, $INVALID_DECOMP_LOCATION, $log_file);
    ##TODO 1: call the exit code from ExitCodes.pm
    # insert error message into notification spool table
    $notifier->spool(
        'HRRT_PET insertion'   , $message,   0,
        'HRRT_PET_insertion.pl', $upload_id, 'Y',
        'N'
    );
    ##TODO 1: call the exit code from ExitCodes.pm
    exit $INVALID_DECOMP_LOCATION;

}

# check that upload location exists in the filesystem
unless ( -r $upload_info->{upload_location} ) {

    $message = <<MESSAGE;
    ERROR: The UploadedLocation $upload_info->{upload_location}
    cannot be found or read for UploadID $upload_id.\n\n
MESSAGE
    # write error message in the log file
    $utility->writeErrorLog($message, $INVALID_UPLOAD_LOCATION, $log_file);
    ##TODO 1: call the exit code from ExitCodes.pm
    # insert error message into notification spool table
    $notifier->spool(
        'HRRT_PET insertion'   , $message,   0,
        'HRRT_PET_insertion.pl', $upload_id, 'Y',
        'N'
    );
    ##TODO 1: call the exit code from ExitCodes.pm
    exit $INVALID_UPLOAD_LOCATION;

}

# check that no HRRT archive ID is already associated to that UploadID
#TODO: uncomment
#if ( $upload_info->{hrrt_archive_ID} ) {
#
#    $message = <<MESSAGE;
#    ERROR: This HRRT study upload ID $upload_id appears to be already inserted
#    into the hrrt_archive tables
#    (HrrtArchiveID=$upload_info->{hrrt_archive_ID}).\n\n
#MESSAGE
#    # write error message in the log file
#    $utility->writeErrorLog(
#        $message, $HRRT_ARCHIVE_ALREADY_INSERTED, $log_file
#    );
#    ##TODO 1: call the exit code from ExitCodes.pm
#    # insert error message into notification spool table
#    $notifier->spool(
#        'HRRT_PET insertion'   , $message,   0,
#        'HRRT_PET_insertion.pl', $upload_id, 'Y',
#        'N'
#    );
#    ##TODO 1: call the exit code from ExitCodes.pm
#    exit $HRRT_ARCHIVE_ALREADY_INSERTED;
#
#}





#TODO: move the BIC check commented here to the imagingUpload run PETHRRT script
# check if the dataset comes from the BIC HRRT scanner
#my @result = `grep -r BIC $decompressed_location`;
#$bic = 1 if (@result); # set $bic to 1 if dataset is




##### Create the archive summary object

# determine the target_location
my $target_location = $data_dir
                      . "/HRRTarchive/";

my $archive = NeuroDB::HRRTSUM->new(
    $upload_info->{decompressed_location}, $target_location, $bic
);

# grep the final target location directory from $archive and create the target
# location directory if it does not exist yet
$target_location = $archive->{target_dir};
mkdir $target_location unless ( -e $target_location );


##### Create the tar file

#TODO: uncomment
## determine where the name and path of the archived HRRT dataset
#my $final_target  = $target_location
#                    . "/HRRT_" . $archive->{study_info}->{date_acquired}
#                    . "_"      . basename($archive->{source_dir})
#                    . ".tgz";
#if ( -e $final_target ) {
#    print "\nTarget already exists.\n\n";
#    exit 2; #TODO 1: call the exit code from ExitCodes.pm
#}
#
## create the tar file and get its md5sum
#my $to_tar = $upload_info->{decompressed_location};
#my $tar_cmd = "tar -czf $final_target $to_tar/*";
#print "\nCreating a tar with the following command: \n $tar_cmd\n" if $verbose;
#system($tar_cmd);
#my $md5sumArchive = NeuroDB::HRRTSUM::md5sum($final_target);
#
#
#
#
###### Register the HRRT archive into the database
#
#print "\nAdding archive info into the database\n" if $verbose;
#my $archiveLocation = $final_target;
#$archiveLocation =~ s/$data_dir//g;
#my $success = $archive->database(
#    $dbh, $md5sumArchive, $archiveLocation, $upload_id
#);
#
#if ($success) {
#    print "\nDone adding HRRT archive info into the database\n" if $verbose;
#} else {
#    print "\nThe database command failed\n";
#    exit ; #TODO 1: call the exit code from ExitCodes.pm
#}




##### Loop through ECAT files

#my $success; # TODO: remove this once uncommenting above

my $success = 1;
my $minc_created = 0;
my $minc_inserted = 0;

foreach my $ecat_file ( @{ $archive->{ecat_files} } ) {

    # check if there is a MINC file associated to the ECAT file
    my $minc_file = NeuroDB::MincUtilities::ecat2minc( $ecat_file );
    unless ( $minc_file ) {
        $message = <<MESSAGE;
    ERROR: MINC file $minc_file does not exist and could not be created based
    on $ecat_file.\n\n
MESSAGE
        # write error message in the log file
        $utility->writeErrorLog(
            $message, $MINC_FILE_NOT_FOUND, $log_file
        );
        ##TODO 1: call the exit code from ExitCodes.pm
        # insert error message into notification spool table
        $notifier->spool(
            'HRRT_PET insertion'   , $message,   0,
            'HRRT_PET_insertion.pl', $upload_id, 'Y',
            'N'
        );
        ##TODO 1: call the exit code from ExitCodes.pm
        exit $MINC_FILE_NOT_FOUND;
    }
    $minc_created++;

    # if it is a BIC dataset, we know a few things
    my $protocol;
    if ($bic) {

        # append values from the .m parameter file to the MINC header
        $success = $archive->insertBicMatlabHeader( $minc_file );
        #TODO exit if undef success

        # grep the acquisition protocol from the MINC header
        $protocol = NeuroDB::MincUtilities::fetch_header_info(
            'matlab_param:PROTOCOL', $minc_file, '$3, $4, $5, $6'
        );

    }

    # TODO: copy Settings option into profileTemplate
    my $acquisition_protocol = &Settings::determineHRRTprotocol(
        $protocol, $ecat_file
    );

    # register MINC using minc_insertion.pl
    my $minc_insert_cmd = "minc_insertion.pl "
                          . " -profile "  . $profile
                          . " -mincPath " . $minc_file
                          . " -uploadID " . $upload_id
                          . " -acquisition_protocol " . $acquisition_protocol
                          . " -create_minc_pics "
                          . " -bypass_extra_file_checks "
                          . " -hrrt ";
    #my $output = system($minc_insert_cmd);
    #$output = $output >> 8;
    #if ($output == 0) {
    #    $minc_inserted++;
    #}

    # append the ecat file into the parameter file table
    my $fileref = NeuroDB::File->new(\$dbh);
    $fileref->loadFileFromDisk($minc_file);
    my $fileID = NeuroDB::DBI::getRegisteredFileIDUsingMd5hash(
        \$fileref, $dbh
    );

    $archive->appendEcatToRegisteredMinc($fileID, $ecat_file, $data_dir, $dbh);

}



# TODO: update MRI upload table
# update following fields: InsertionComplete = 1, number_of_mincInserted,
# number_of_mincCreated, SessionID, Inserting = 0



exit 0; ##TODO 1: replace exit 0 by $NeuroDB::ExitCodes::$SUCCESS




sub logHeader () {
    print LOG "
----------------------------------------------------------------
            AUTOMATED PET HRRT INSERTION
----------------------------------------------------------------
*** Date and time of insertion : $today
*** tmp dir location           : $TmpDir
";
}


#! /usr/bin/perl

use strict;
use warnings;
use Getopt::Tabular;
use File::Temp qw/ tempdir /;
use Date::Parse;
use File::Basename;
use File::Path qw/make_path/;

use NeuroDB::DBI;
use NeuroDB::Notify;
use NeuroDB::MRIProcessingUtility;
use NeuroDB::HRRT;
use NeuroDB::MincUtilities;
use NeuroDB::File;
use NeuroDB::ExitCodes;
use NeuroDB::Utilities;




# ------------------------------------------------------------------
## Table-driven argument parsing
# ------------------------------------------------------------------

# Initialize variables for Getopt::Tabular
my $profile;
my $upload_id;
my $verbose = 0;
my $bic     = 0;
my $clobber = 0;
my $skip_archival = 0;
my @args;

# Describe the usage to be displayed by Getopt::Tabular
my  $Usage  =   <<USAGE;

This script takes an upload ID of a PET HRRT study to insert it into the
database with information about the list of files contained in the upload. It
will also grep the ECAT7 files to insert their header information into the
database.

NOTES:
  - in case the MINC files are already present in the PET HRRT study, it
    will use the already created MINC instead of creating them.
  - the current script work well with datasets coming from the PET HRRT scanner of
    the BIC (at the MNI). This pipeline may need to be adapted for another PET HRRT
    scanner but given that there is only 7 of those scanners in the world and there
    is no standard as to how the data is collected and converted, we will adapt the
    pipeline for other PET HRRT scanners when the need comes.

Usage: perl HRRT_PET_archive.pl [options]

-help for options

USAGE

# Set the variable descriptions to be used by Getopt::Tabular
my $profile_desc   = "Name of config file in ./config.";
my $upload_id_desc = "ID of the uploaded imaging archive";
my $bic_desc       = "whether the datasets comes from the BIC HRRT scanner";
my $clobber_desc   = "Use this option only if you want to replace the resulting tarball!";
my $skip_archival_desc = "Use this option to skip the insertion of the study into"
                          . " the hrrt_archive table in case the study was already"
                          . " archived. Will only run the MINC & ECAT7 insertion"
                          . " part after validation of the associated HRRT archive.";

# Initialize the arguments table
my @args_table = (

    [ "Mandatory options", "section" ],

        [ "-profile",   "string",  1, \$profile,   $profile_desc   ],
        [ "-upload_id", "string",  1, \$upload_id, $upload_id_desc ],

    [ "Advanced options", "section" ],

        [ "-verbose",   "boolean", 1, \$verbose,   "Be verbose"  ],
        [ "-clobber",   "boolean", 1, \$clobber,   $clobber_desc ],

    [ "Optional options", "section" ],

        [ "-bic",           "boolean", 1, \$bic,           $bic_desc           ],
        [ "-skip_archival", "boolean", 1, \$skip_archival, $skip_archival_desc ]

);

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) ||
    exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

# Input option error checking
if (!$profile) {
    print STDERR "$Usage\n\tERROR: You must specify a profile.\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

{ package Settings; do "$ENV{LORIS_CONFIG}/$profile" }
if ($profile && !@Settings::db)    {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}




# ------------------------------------------------------------------
## Establish database connection
# ------------------------------------------------------------------

# old database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# new Moose database connection
my $db  = NeuroDB::Database->new(
    databaseName => $Settings::db[0],
    userName     => $Settings::db[1],
    password     => $Settings::db[2],
    hostName     => $Settings::db[3]
);
$db->connect();




# ------------------------------------------------------------------
## Get config settings using ConfigOB
# ------------------------------------------------------------------

my $configOB = NeuroDB::objectBroker::ConfigOB->new(db => $db);

my $data_dir = $configOB->getDataDirPath();




# ------------------------------------------------------------------
## For the log, temp directories and notification spools
# ------------------------------------------------------------------

# determine local time
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $today = sprintf( "%4d-%02d-%02d %02d:%02d:%02d",
    $year+1900, $mon+1, $mday, $hour, $min, $sec
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
    $db, \$dbh, 0, $TmpDir, $log_file, $verbose, $profile
);




# ------------------------------------------------------------------------------
## Verify that the provided upload ID refers to a valid uploaded entry in
## the database and in the filesystem, and that it did not get already archived
# ------------------------------------------------------------------------------

# grep the UploadedLocation for the UploadID
my $upload_info = NeuroDB::HRRT::getHrrtUploadInfo( $dbh, $upload_id );

# check that the upload ID was valid
unless ( $upload_info ) {

    # if no upload info, exits with message that did not find this upload ID
    $message = <<MESSAGE;
    ERROR: Invalid UploadID $upload_id.\n\n
MESSAGE
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::INVALID_UPLOAD_ID, $log_file
    );
    # insert error message into notification spool table
    $notifier->spool(
        'HRRT_PET insertion'   , $message,   0,
        'HRRT_PET_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::INVALID_UPLOAD_ID;

}

# check that decompressed and upload location exist in the filesystem unless -skip_archival
unless ($skip_archival) {

    unless (-r $upload_info->{decompressed_location}) {

        $message = <<MESSAGE;
    ERROR: The decompressedLocation $upload_info->{decompressed_location}
    cannot be found or read for UploadID $upload_id.\n\n
MESSAGE
        # write error message in the log file
        $utility->writeErrorLog(
            $message, $NeuroDB::ExitCodes::INVALID_DECOMP_LOCATION, $log_file
        );
        # insert error message into notification spool table
        $notifier->spool(
            'HRRT_PET insertion', $message, 0,
            'HRRT_PET_insertion.pl', $upload_id, 'Y',
            'N'
        );
        exit $NeuroDB::ExitCodes::INVALID_DECOMP_LOCATION;

    }

    # check that upload location exists in the filesystem
    unless (-r $upload_info->{upload_location}) {

        $message = <<MESSAGE;
    ERROR: The UploadedLocation $upload_info->{upload_location}
    cannot be found or read for UploadID $upload_id.\n\n
MESSAGE
        # write error message in the log file
        $utility->writeErrorLog(
            $message, $NeuroDB::ExitCodes::INVALID_UPLOAD_LOCATION, $log_file
        );
        # insert error message into notification spool table
        $notifier->spool(
            'HRRT_PET insertion', $message, 0,
            'HRRT_PET_insertion.pl', $upload_id, 'Y',
            'N'
        );
        exit $NeuroDB::ExitCodes::INVALID_UPLOAD_LOCATION;

    }

}

# check that no HRRT archive ID is already associated to that UploadID when
# -skip_archival is not set in the call to the script
if ( $upload_info->{hrrt_archive_ID} && !$skip_archival) {

    $message = <<MESSAGE;
    ERROR: This HRRT study upload ID $upload_id appears to be already inserted
    into the hrrt_archive tables (HrrtArchiveID=$upload_info->{hrrt_archive_ID}).
    Consider running the script with the option -skip_archival.\n\n
MESSAGE
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::HRRT_ALREADY_INSERTED, $log_file
    );
    # insert error message into notification spool table
    $notifier->spool(
        'HRRT_PET insertion'   , $message,   0,
        'HRRT_PET_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::HRRT_ALREADY_INSERTED;

}

# check that there is an HRRT archive ID is associated to that UploadID when
# -skip_archival is set in the call to the script
if ( !$upload_info->{hrrt_archive_ID} && $skip_archival) {

    $message = <<MESSAGE;
    ERROR: This HRRT study upload ID $upload_id does not appear to have been
    previously archived as no associated HrrtArchiveID could be found.
    Consider running the script without the option -skip_archival to insert
    the record into the hrrt_archive tables.\n\n
MESSAGE
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::HRRT_ARCHIVE_INSERTION_FAILURE, $log_file
    );
    # insert error message into notification spool table
    $notifier->spool(
        'HRRT_PET insertion'   , $message,   0,
        'HRRT_PET_insertion.pl', $upload_id, 'Y',
        'N'
    );
    exit $NeuroDB::ExitCodes::HRRT_ARCHIVE_INSERTION_FAILURE;

}



# ------------------------------------------------------------------
## Create the archive summary object
# ------------------------------------------------------------------

# determine the target_location
my $target_location = $data_dir . "/hrrtarchive/";

my $archive_obj = $skip_archival ? decompress_hrrt_archive() : run_hrrt_archival();




# ------------------------------------------------------------------
## Loop through ECAT files
# ------------------------------------------------------------------

my $minc_created  = 0;
my $minc_inserted = 0;
my $sessionID;

foreach my $ecat_file ( @{ $archive_obj->{ecat_files} } ) {

    # check if there is a MINC file associated to the ECAT file
    my $minc_file = NeuroDB::MincUtilities::ecat2minc( $ecat_file );
    unless ( $minc_file ) {
        $message = <<MESSAGE;
    ERROR: MINC file $minc_file does not exist and could not be created based
    on $ecat_file.\n\n
MESSAGE
        # write error message in the log file
        $utility->writeErrorLog(
            $message, $NeuroDB::ExitCodes::MINC_FILE_NOT_FOUND, $log_file
        );
        # insert error message into notification spool table
        $notifier->spool(
            'HRRT_PET insertion'   , $message,   0,
            'HRRT_PET_insertion.pl', $upload_id, 'Y',
            'N'
        );
        exit $NeuroDB::ExitCodes::MINC_FILE_NOT_FOUND;
    }
    $minc_created++;

    # create a hash with MINC information and compute MINC md5hash to be used
    # later on to fetch the fileID of the registered MINC file.
    my $mincref = NeuroDB::File->new(\$dbh);
    $mincref->loadFileFromDisk($minc_file);
    my $md5hash = &NeuroDB::MRI::compute_hash(\$mincref);

    # if it is a BIC dataset, we know a few things...
    my $protocol;
    if ($bic) {

        # append values from the .m parameter file to the MINC header
        my $success = $archive_obj->insertBicMatlabHeader( $minc_file );
        unless ($success) {
            $message = <<MESSAGE;
    ERROR: Matlab information could not be inserted into the header of file
    $minc_file.\n\n
MESSAGE
            # write error message in the log file
            $utility->writeErrorLog(
                $message,  $NeuroDB::ExitCodes::HEADER_INSERT_FAILURE,
                $log_file
            );
            # insert error message into notification spool table
            $notifier->spool(
                'HRRT_PET insertion'   , $message,   0,
                'HRRT_PET_insertion.pl', $upload_id, 'Y',
                'N'
            );
            exit $NeuroDB::ExitCodes::HEADER_INSERT_FAILURE;
        }

        # grep the acquisition protocol from the MINC header
        $protocol = NeuroDB::MincUtilities::fetch_header_info(
            'matlab_param:PROTOCOL', $minc_file, '$3, $4, $5, $6'
        );
        unless ($protocol) {
            $message = "\tERROR: Protocol not found for $minc_file.\n\n";
            # write error message in the log file
            $utility->writeErrorLog(
                $message, $NeuroDB::ExitCodes::UNKNOWN_PROTOCOL, $log_file
            );
            # insert error message into notification spool table
            $notifier->spool(
                'HRRT_PET insertion'   , $message,   0,
                'HRRT_PET_insertion.pl', $upload_id, 'Y',
                'N'
            );
            exit $NeuroDB::ExitCodes::UNKNOWN_PROTOCOL;
        }

    }

    # determine the acquisition protocol for the file
    my $acquisition_protocol = &Settings::determineHRRTprotocol($protocol, basename($ecat_file));
    my $acquisitionProtocolID = NeuroDB::MRI::scan_type_text_to_id($acquisition_protocol, $db);
    unless (defined $acquisitionProtocolID) {
        $message = "\tProtocol $acquisition_protocol not found in mri_scan_type for $minc_file.\n\n";
        # write error message in the log file
        $utility->writeErrorLog(
            $message, $NeuroDB::ExitCodes::UNKNOWN_PROTOCOL, $log_file
        );
        # insert error message into notification spool table
        $notifier->spool(
            'HRRT_PET insertion'   , $message,   0,
            'HRRT_PET_insertion.pl', $upload_id, 'Y',
            'N'
        );
        next;
    }


    # register MINC using minc_insertion.pl
    my $minc_insert_cmd = "minc_insertion.pl "
                          . " -profile "  . $profile
                          . " -mincPath " . $minc_file
                          . " -uploadID " . $upload_id
                          . " -acquisition_protocol " . $acquisition_protocol
                          . " -create_minc_pics "
                          . " -bypass_extra_file_checks "
                          . " -hrrt ";
    my $output = system($minc_insert_cmd);
    $output = $output >> 8;
    if ($output == 0) {
        $minc_inserted++;
    }

    # append the ecat file into the parameter file table
    my $fileID = NeuroDB::HRRT::getRegisteredFileIdUsingMd5hash($md5hash, $dbh);
    unless ($fileID) {
        $message = "\tERROR: $minc_file not inserted into the files table.\n\n";
        # write error message in the log file
        $utility->writeErrorLog(
            $message, $NeuroDB::ExitCodes::MINC_INSERTION_FAILURE, $log_file
        );
        # insert error message into notification spool table
        $notifier->spool(
            'HRRT_PET insertion'   , $message,   0,
            'HRRT_PET_insertion.pl', $upload_id, 'Y',
            'N'
        );
        exit $NeuroDB::ExitCodes::MINC_INSERTION_FAILURE;
    }
    $archive_obj->appendEcatToRegisteredMinc($fileID, $ecat_file, $data_dir, $dbh);

    # grep the session ID associated to the file ID
    $sessionID = NeuroDB::HRRT::getSessionIdFromFileId($fileID, $dbh);
    unless ($sessionID) {
        $message = "\tERROR: could not find SessionID for FileID=$fileID.\n\n";
        # write error message in the log file
        $utility->writeErrorLog(
            $message, $NeuroDB::ExitCodes::GET_SESSION_ID_FAILURE,
            $log_file
        );
        # insert error message into notification spool table
        $notifier->spool(
            'HRRT_PET insertion'   , $message,   0,
            'HRRT_PET_insertion.pl', $upload_id, 'Y',
            'N'
        );
        exit $NeuroDB::ExitCodes::GET_SESSION_ID_FAILURE;
    }

}

# update the SessionID field of hrrt_archive with $sessionID
my $hrrtArchiveID = $archive_obj->{hrrt_archive_ID};
NeuroDB::HRRT::updateHrrtArchiveSessionID($hrrtArchiveID, $sessionID, $dbh);

# update mri_upload table
NeuroDB::HRRT::updateHrrtUploadInfo(
    {
        "InsertionComplete"      => 1,
        "number_of_mincInserted" => $minc_inserted,
        "number_of_mincCreated"  => $minc_created,
        "SessionID"              => $sessionID,
        "Inserting"              => 0
    },
    $upload_id,
    $dbh
);


exit $NeuroDB::ExitCodes::SUCCESS;




sub logHeader () {
    print LOG "
----------------------------------------------------------------
            AUTOMATED PET HRRT INSERTION
----------------------------------------------------------------
*** Date and time of insertion : $today
*** tmp dir location           : $TmpDir
";
}



=pod

=head3 decompress_hrrt_archive()

Finds the HRRT archive file in the file system based on the C<HrrtArchiveID> file
stored in the C<mri_upload*> tables and extracts it in the temporary directory
created by this script.

RETURNS: a hash with all the information related to the HRRT Archive

=cut

sub decompress_hrrt_archive {

    my $archive_location = NeuroDB::HRRT::getHrrtArchiveLocationFromHrrtArchiveID(
        $upload_info->{hrrt_archive_ID}, $dbh
    );

    my $cmd = "cd $TmpDir; tar -xf $data_dir/$archive_location";
    print "\nExtracting with the following command: \n $cmd\n" if $verbose;
    system($cmd);

    my $archive = NeuroDB::HRRT->new($TmpDir, $target_location, $bic);
    $archive->{hrrt_archive_ID} = $upload_info->{hrrt_archive_ID};

    return $archive;
}




=pod

=head3 run_hrrt_archival()

Creates an archive of the HRRT dataset and insert the information regarding that
dataset as well as the path to the created archive into the hrrt_archive tables.

RETURNS: a hash with all the information related to the HRRT Archive

=cut

sub run_hrrt_archival {

    # ------------------------------------------------------------------
    ## Create the archive summary object
    # ------------------------------------------------------------------
    my $archive = NeuroDB::HRRT->new(
        $upload_info->{decompressed_location}, $target_location, $bic
    );

    # grep the final target location directory from $archive and create the target
    # location directory if it does not exist yet
    $target_location = $archive->{target_dir};
    make_path($target_location) unless ( -e $target_location );




    # ------------------------------------------------------------------
    ## Create the tar file
    # ------------------------------------------------------------------

    # determine where the name and path of the archived HRRT dataset
    my $final_target  = $target_location
        . "/HRRT_" . $archive->{study_info}->{date_acquired}
        . "_"      . basename($archive->{decompressed_dir})
        . ".tgz";
    if ( -e $final_target && !$clobber ) {
        print STDERR "\nTarget already exists. Use -clobber to overwrite!\n\n";
        exit $NeuroDB::ExitCodes::TARGET_EXISTS_NO_CLOBBER;
    }

    # create the tar file and get its blake2b hash
    my $to_tar_dir = dirname($upload_info->{decompressed_location});
    my $study_dir  = basename($upload_info->{decompressed_location});

    my $tar_cmd = "tar -C $to_tar_dir -czf $final_target $study_dir";
    print "\nCreating a tar with the following command: \n $tar_cmd\n" if $verbose;
    system($tar_cmd);
    my $blake2bArchive = NeuroDB::Utilities::blake2b_hash($final_target);




    # ------------------------------------------------------------------
    ## Register the HRRT archive into the database
    # ------------------------------------------------------------------

    print "\nAdding archive info into the database\n" if $verbose;
    my $archiveLocation = $final_target;
    $archiveLocation =~ s/$data_dir\///g;
    my $newHrrtArchiveID = $archive->insert_hrrt_tables(
        $dbh, $blake2bArchive, $archiveLocation, $upload_id
    );

    if ($newHrrtArchiveID) {
        print "\nDone adding HRRT archive info into the database\n" if $verbose;
    } else {
        print STDERR "\nThe database command failed\n";
        exit $NeuroDB::ExitCodes::HRRT_ARCHIVE_INSERTION_FAILURE;
    }

    $archive->{hrrt_archive_ID} = $newHrrtArchiveID;

    return $archive;
}

# Generic TODOs:

##TODO 1: once ExitCodes.pm class merged, replace exit codes by the variables
# from that class


use strict;
use warnings;
use Getopt::Tabular;
use File::Temp qw/ tempdir /;
use Date::Parse;
use File::Basename;
use String::ShellQuote;


###### Import NeuroDB libraries to be used
use NeuroDB::DBI;
use NeuroDB::Notify;
use NeuroDB::MRIProcessingUtility;
use NeuroDB::HRRTSUM;
##TODO 1: add line use NeuroDB::ExitCodes;


##TODO 1: move those exit codes to ExitCodes.pm
my $INVALID_UPLOAD_ID       = 150; # invalid upload ID
my $INVALID_UPLOAD_LOCATION = 151; # invalid upload location
my $INVALID_DECOMP_LOCATION = 152; # invalid decompressed location
my $HRRT_ARCHIVE_ALREADY_INSERTED = 153; # if HRRT archive already exists in DB

###### Table-driven argument parsing

# Initialize variables for Getopt::Tabular
my $profile   = undef;
my $upload_id = undef;
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
(my $query = <<QUERY) =~ s/\n/ /gm;
SELECT UploadLocation, DecompressedLocation, HrrtArchiveID
FROM mri_upload
LEFT JOIN mri_upload_rel ON ( mri_upload.UploadID = mri_upload_rel.UploadID )
WHERE mri_upload.UploadID=?
QUERY
my $sth = $dbh->prepare($query);
$sth->execute($upload_id);

unless ( $sth->rows > 0 ) {

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

# grep the result of the query into variables
my @result = $sth->fetchrow_array();
my $upload_location       = $result[0];
my $decompressed_location = $result[1];
my $hrrt_archive_ID       = $result[2];

# check that decompressed location exists in the filesystem
unless ( -r $decompressed_location ) {
    $message = <<MESSAGE;
    ERROR: The decompressedLocation $decompressed_location cannot be found or
    read for UploadID $upload_id.\n\n
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
unless ( -r $upload_location ) {
    $message = <<MESSAGE;
    ERROR: The UploadedLocation $upload_location cannot be found or
    read for UploadID $upload_id.\n\n
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
if ( $hrrt_archive_ID ) {
    $message = <<MESSAGE;
    ERROR: This HRRT study upload ID $upload_id appears to be already inserted
    into the hrrt_archive tables (HrrtArchiveID=$hrrt_archive_ID).\n\n
MESSAGE
    # write error message in the log file
    $utility->writeErrorLog(
        $message, $HRRT_ARCHIVE_ALREADY_INSERTED, $log_file
    );
    ##TODO 1: call the exit code from ExitCodes.pm
    # insert error message into notification spool table
    $notifier->spool(
        'HRRT_PET insertion'   , $message,   0,
        'HRRT_PET_insertion.pl', $upload_id, 'Y',
        'N'
    );
    ##TODO 1: call the exit code from ExitCodes.pm
    exit $HRRT_ARCHIVE_ALREADY_INSERTED;
}





#TODO: move the BIC check commented here to the imagingUpload run PETHRRT script
# check if the dataset comes from the BIC HRRT scanner
#my @result = `grep -r BIC $decompressed_location`;
#$bic = 1 if (@result); # set $bic to 1 if dataset is




##### Create the archive summary object

# determine the target_location
my $target_location = $data_dir
                      . "/HRRTarchive/";

my $archive = NeuroDB::HRRTSUM->new(
    $decompressed_location, $target_location, $bic
);

# grep the final target location directory from $archive and create the target
# location directory if it does not exist yet
$target_location = $archive->{target_dir};
mkdir $target_location unless ( -e $target_location );


##### Create the tar file
#
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
#my $tar_cmd = "tar -czf $final_target $decompressed_location/*";
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
#my $success = $archive->database( $dbh, $md5sumArchive, $upload_id );
#
#if ($success) {
#    print "\nDone adding HRRT archive info into the database\n" if $verbose;
#} else {
#    print "\nThe database command failed\n";
#    exit ; #TODO 1: call the exit code from ExitCodes.pm
#}




##### Loop through ECAT files

my $success; # TODO: remove this once uncommenting above

foreach my $ecat_file ( @{ $archive->{ecat_files} } ) {

    # check if there is a MINC file associated to the ECAT file
    my $dirname   = dirname( $ecat_file );
    my $minc_file = $dirname . "/" . basename( $ecat_file, '.v' ) . ".mnc";
    unless ( -e $minc_file ) {
        my $ecat2mnc_cmd = "ecattominc -quiet "
                           . $ecat_file   . " "
                           . $minc_file;
        system($ecat2mnc_cmd);
    }

    # if it is a BIC dataset, we know a few things
    my $protocol;
    if ($bic) {

        # append values from the .m parameter file to the MINC header
        foreach my $key ( keys %{ $archive->{matlab_info} } ) {
            my $arg = "matlab_param:" . $key;
            my $val = $archive->{matlab_info}->{$key};
            $val = shell_quote $val;
            $success = modify_header($arg, $val, $minc_file, '$3, $4, $5, $6');
            exit unless ( $success ); #TODO 1: exit code + logging
        }

        # insert proper scanner information
        modify_header(
            'study:manufacturer',  $archive->{study_info}->{manufacturer},
            $minc_file,            '$3, $4, $5, $6'
        );
        modify_header(
            'study:device_model',  $archive->{study_info}->{scanner_model},
            $minc_file,            '$3, $4, $5, $6'
        );
        modify_header(
            'study:serial_no',     $archive->{study_info}->{system_type},
            $minc_file,            '$3, $4, $5, $6'
        );

        # TODO: maybe append other values if needed?

        # grep the acquisition protocol from the profile file
        $protocol = fetch_header_info(
            'matlab_param:PROTOCOL', $minc_file, '$3, $4, $5, $6'
        );

    }

    # TODO: copy Settings option into profileTemplate
    my $acquisition_protocol = &Settings::determineHRRTprotocol(
        $protocol, $ecat_file
    );

    # TODO: register MINC using minc_insertion.pl (need to test the command)
    my $minc_insert_cmd = "minc_insertion.pl "
                          . " -profile " . $profile
                          . " -mincPath" . $minc_file
                          . " -acquisition_protocol " . $acquisition_protocol
                          . " -bypass_extra_file_checks";
    print $minc_insert_cmd;


    # TODO: append the ecat file into the parameter file table

}


# TODO: call the mass minc pic script





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


=pod
Function that runs minc_modify_header and insert
minc header information if not already inserted.
Inputs:  - $argument: argument to be inserted in minc header
         - $value: value of the argument to be inserted in minc header
         - $minc: minc file
         - $awk: awk information to check if argument not already inserted in minc header
Outputs: - 1 if argument was indeed inserted into the minc file
         - undef otherwise
=cut
sub modify_header {
    my ( $argument, $value, $minc, $awk ) = @_;

    # check if header information not already in minc file
    my $hdr_val = fetch_header_info( $argument, $minc, $awk );

    # insert mincheader unless mincheader field already inserted and
    # its header value equals the value to insert
    my  $cmd = "minc_modify_header -sinsert $argument=$value $minc";
    system($cmd) unless ( ($hdr_val) && ($value eq $hdr_val) );

    # check if header information was indeed inserted in minc file
    my $hdr_val2 = fetch_header_info( $argument, $minc, $awk );

    if ($hdr_val2) {
        return 1;
    } else {
        return undef;
    }
}



=pod
Function that fetch header information in minc file
Inputs:  - $field: field to look for in minc header
         - $minc: minc file
         - $awk: awk information to check if argument not already inserted in minc header
         - $keep_semicolon: if defined, keep semicolon at the end of the value extracted
Outputs: - $value: value of the field found in the minc header
=cut
sub fetch_header_info {
    my ( $field, $minc, $awk, $keep_semicolon ) = @_;

    my $cmd = "mincheader " . $minc
              . " | grep "  . $field
              . " | awk '{print $awk}' "
              . " | tr '\n' ' ' ";

    my $val = `$cmd`;
    #my $val   = `mincheader $minc | grep $field | awk '{print $awk}' | tr'\n' ' '`;
    my $value = $val if ( $val !~ /^\s*"*\s*"*\s*$/ );
    if ($value) {
        $value =~ s/^\s+//; # remove leading spaces
        $value =~ s/\s+$//; # remove trailing spaces
        # remove ";" unless $keep_semicolon is defined
        $value =~ s/;// unless ( $keep_semicolon );
    } else {
        return undef;
    }

    return  ($value);
}


#TODO: in another PR, move minc functions to library readable by DTI & NeuroDB

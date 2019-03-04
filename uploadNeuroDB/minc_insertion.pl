#! /usr/bin/perl

=pod

=head1 NAME

minc_insertion.pl -- Insert MINC files into the LORIS database system

=head1 SYNOPSIS

perl minc_insertion.pl C<[options]>

Available options are:

-profile     : name of the config file in C<../dicom-archive/.loris_mri>

-uploadID    : The upload ID from which this MINC was created

-reckless    : uploads data to database even if study protocol
               is not defined or violated

-force       : forces the script to run even if DICOM archive validation failed

-mincPath    : the absolute path to the MINC file

-tarchivePath: the absolute path to the tarchive file

-globLocation: loosens the validity check of the tarchive allowing
               for the possibility that the tarchive was moved
               to a different directory

-newScanner  : if set [default], new scanner will be registered

-xlog        : opens an xterm with a tail on the current log file

-verbose     : if set, be verbose

-acquisition_protocol    : suggests the acquisition protocol to use

-create_minc_pics        : creates the MINC pics

-bypass_extra_file_checks: bypasses extra file checks


=head1 DESCRIPTION

The program inserts MINC files into the LORIS database system. It performs the
four following actions:

- Loads the created MINC file and then sets the appropriate parameter for
the loaded object:

   (
    ScannerID,  SessionID,      SeriesUID,
    EchoTime,   PendingStaging, CoordinateSpace,
    OutputType, FileType,       TarchiveSource,
    Caveat
   )

- Extracts the correct acquisition protocol

- Registers the scan into the LORIS database by changing the path to the MINC
and setting extra parameters

- Finally sets the series notification

=head2 Methods

=cut

use strict;
use warnings;
use Carp;
use Getopt::Tabular;
use FileHandle;
use File::Basename;
use File::Temp qw/ tempdir /;
use Data::Dumper;
use FindBin;
use Cwd qw/ abs_path /;

# These are the NeuroDB modules to be used
use lib "$FindBin::Bin";
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::Notify;
use NeuroDB::MRIProcessingUtility;
use NeuroDB::ExitCodes;


my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.24 $ 
    =~ /: (\d+)\.(\d+)/;
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) 
    =localtime(time);
my $date = sprintf(
                "%4d-%02d-%02d %02d:%02d:%02d",
                $year+1900,$mon+1,$mday,$hour,$min,$sec
           );
my $debug       = 0;  
my $message     = '';
my $upload_id;
my $verbose     = 0;           # default, overwritten if scripts are run with -verbose
my $notify_detailed   = 'Y';   # notification_spool message flag for messages to be displayed 
                               # with DETAILED OPTION in the front-end/imaging_uploader 
my $notify_notsummary = 'N';   # notification_spool message flag for messages to be displayed 
                               # with SUMMARY Option in the front-end/imaging_uploader 
my $profile     = undef;       # this should never be set unless you are in a 
                               # stable production environment
my $reckless    = 0;           # this is only for playing and testing. Don't 
                               # set it to 1!!!
my $force       = 0;           # This is a flag to force the script to run  
                               # Even if the validation has failed
my $NewScanner  = 1;           # This should be the default unless you are a 
                               # control freak
my $xlog        = 0;           # default should be 0
my $bypass_extra_file_checks=0;# If you need to bypass the extra_file_checks, set to 1.
my $acquisitionProtocol=undef; # Specify the acquisition Protocol also bypasses the checks
my $acquisitionProtocolID;     # acquisition Protocol id
my $extra_validation_status;   # Initialise the extra validation status
my $create_minc_pics    = 0;   # Default is 0, set the option to overide.
my $globArchiveLocation = 0;   # whether to use strict ArchiveLocation strings
                               # or to glob them (like '%Loc')
my $template    = "TarLoad-$hour-$min-XXXXXX"; # for tempdir
my ($tarchive,%studyInfo,$minc);

################################################################
#### These settings are in a config file (profile) #############
################################################################
my @opt_table = (
                 ["Basic options","section"],

                 ["-profile","string",1, \$profile, "name of config file". 
                 " in ../dicom-archive/.loris_mri"],

                 ["-uploadID", "string", 1, \$upload_id, "The upload ID " .
                  "from which this MINC was created"],

                 ["Advanced options","section"],

                 ["-reckless", "boolean", 1, \$reckless,"Upload data to". 
                 " database even if study protocol is not ".
                 "defined or violated."],

                 ["-force", "boolean", 1, \$force,"Forces the script to run". 
                 " even if the DICOM archive validation has failed."],
  
                 ["-mincPath","string",1, \$minc, "The absolute path". 
                  " to minc-file"],

                 ["-tarchivePath","string",1, \$tarchive, "The absolute path". 
                  " to tarchive-file"],

                 ["-globLocation", "boolean", 1, \$globArchiveLocation,
                  "Loosen the validity check of the tarchive allowing for the". 
                  " possibility that the tarchive was moved to a different". 
                  " directory."],

                 ["-newScanner", "boolean", 1, \$NewScanner,
                  "By default a new scanner will be registered if the data".
                  " you upload requires it. You can risk turning it off."],

                 ["Fancy options","section"],

                 ["-xlog", "boolean", 1, \$xlog, "Open an xterm with a tail".
                  " on the current log file."],

                 ["General options","section"],
                 ["-verbose", "boolean", 1, \$verbose, "Be verbose."],

                 ["-acquisition_protocol","string", 1, \$acquisitionProtocol,
                  "Suggest the acquisition protocol to use."],

                 ["-create_minc_pics", "boolean", 1, \$create_minc_pics,
                  "Creates the minc pics."],

                 ["-bypass_extra_file_checks", "boolean", 1, \$bypass_extra_file_checks,
                  "Bypasses extra_file_checks."],
);


my $Help = <<HELP;
*******************************************************************************
Minc Insertion 
*******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo


The program does the following:

- Loads the created MINC file and then sets the appropriate parameter for
  the loaded object (i.e ScannerID, SessionID,SeriesUID, EchoTime, 
                     PendingStaging, CoordinateSpace , OutputType , FileType
                     ,TarchiveSource and Caveat)
- Extracts the correct acquition protocol
- Registers the scan into db by first changing the minc-path and setting extra
  parameters
- Finally sets the series notification

Documentation: perldoc minc_insertion.pl

HELP
my $Usage = <<USAGE;
usage: $0 </path/to/DICOM-tarchive> [options]
       $0 -help to list options

USAGE
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

if (!$ENV{LORIS_CONFIG}) {
    print STDERR "\n\tERROR: Environment variable 'LORIS_CONFIG' not set\n\n";
    exit $NeuroDB::ExitCodes::INVALID_ENVIRONMENT_VAR; 
}

if (!defined $profile || !-e "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
    print $Help; 
    print STDERR "$Usage\n\tERROR: You must specify a valid and existing profile.\n\n";  
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

if (defined $tarchive && !(-e $tarchive) ) {
    print STDERR "\nERROR: Could not find archive $tarchive. \nPlease, make sure "
        . " the path to the archive is correct. Upload will exit now.\n\n\n";
    exit $NeuroDB::ExitCodes::INVALID_PATH;
}

if ( !($tarchive xor $upload_id xor $force) ) {
    print STDERR "\nERROR: You should either specify an upload ID or a DICOM "
        . "archive path or use the -force option (if no upload ID or DICOM archive "
        . "are available for the MINC file). Make sure that you set only "
        . "one of those options. Upload will exit now.\n\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}

if (!defined $minc || !-e $minc) {
    print STDERR "$Usage\n\tERROR: You must specify a valid and existing "
        . "MINC file with -minc.\n\n";  
    exit $NeuroDB::ExitCodes::INVALID_PATH;
}

# input option error checking
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }

if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}

################################################################
############### Establish database connection ##################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);


## Grep Config Settings
my $data_dir           = NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath'   );
my $create_nii         = NeuroDB::DBI::getConfigSetting(\$dbh, 'create_nii'        );
my $horizontalPics     = NeuroDB::DBI::getConfigSetting(\$dbh, 'horizontalPics'    );
my $tarchiveLibraryDir = NeuroDB::DBI::getConfigSetting(\$dbh, 'tarchiveLibraryDir');
$tarchiveLibraryDir    =~ s/\/$//g;

################################################################
########### Create the Specific Log File #######################
################################################################
my $TmpDir   = tempdir($template, TMPDIR => 1, CLEANUP => 1 );
my @temp     = split(/\//, $TmpDir);
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs";

if (!-d $LogDir) { 
    mkdir($LogDir, 0770); 
}
my $logfile  = "$LogDir/$templog.log";
print "\nlog dir is $LogDir and log file is $logfile \n" if $verbose;
open LOG, ">>", $logfile or die "Error Opening $logfile";
LOG->autoflush(1);
# strings needed for the logHeader, if not set, as an argument, use empty string
my $source_data_for_log = $tarchive // "";
my $upload_id_for_log = $upload_id // "";
&logHeader();

print LOG "\n==> Successfully connected to database \n" if $verbose;

################################################################
################## MRIProcessingUtility object #################
################################################################
my $utility = NeuroDB::MRIProcessingUtility->new(
                  \$dbh,$debug,$TmpDir,$logfile,
                  $verbose
              );

################################################################
############ Construct the notifier object #####################
################################################################
my $notifier = NeuroDB::Notify->new(\$dbh);



################################################################
#################### Check is_valid column #####################
################################################################
my ( $is_valid, $ArchiveLocation );
if ($upload_id) {
    # if the uploadID is passed as an argument, verify that the tarchive was
    # validated
    (my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT
      IsTarchiveValidated,
      ArchiveLocation
    FROM
      mri_upload JOIN tarchive USING (TarchiveID)
    WHERE
      UploadID = ?
QUERY
    print $query . "\n" if $debug;
    my $sth = $dbh->prepare($query);
    $sth->execute($upload_id);
    my @array        = $sth->fetchrow_array;
    $is_valid        = $array[0];
    $ArchiveLocation = $array[1];

    # create the studyInfo object
    %studyInfo = $utility->createTarchiveArray(
        $ArchiveLocation, $globArchiveLocation
    );

} elsif ($tarchive) {
    # if only the tarchive path is given as an argument, find the associated UploadID
    # and check if IsTarchiveValidated is set to 1.
    $ArchiveLocation = $tarchive;
    $ArchiveLocation    =~ s/$tarchiveLibraryDir\/?//g;

    my $where = "WHERE ArchiveLocation='$tarchive'";
    if ($globArchiveLocation) {
        $where = "WHERE ArchiveLocation LIKE '%/" . quotemeta(basename($tarchive)) . "' "
                 . "OR ArchiveLocation = '" . quotemeta(basename($tarchive)) . "'";
    }
    my $query = "SELECT IsTarchiveValidated, UploadID, SourceLocation "
                . "FROM mri_upload "
                . "JOIN tarchive USING (TarchiveID) $where ";
    my $sth   = $dbh->prepare($query);
    print $query . "\n" if $debug;

    $sth->execute();
    my $errorMessage;
    if ($sth->rows == 0) {
        $errorMessage = $globArchiveLocation
            ? "No mri_upload with the same archive location basename as '$tarchive'\n"
            : "No mri_upload with archive location '$tarchive'\n";
        $utility->writeErrorLog(
            $errorMessage, $NeuroDB::ExitCodes::INVALID_ARG, $logfile
        );
        print STDERR $errorMessage;
        exit $NeuroDB::ExitCodes::INVALID_ARG;
    } elsif ($sth->rows > 1) {
        $errorMessage = "\nERROR: found more than one UploadID associated with "
                        . "this ArchiveLocation ($tarchive). Please specify the "
                        . "UploadID to use using the -uploadID option.\n\n";
        $utility->writeErrorLog(
            $errorMessage, $NeuroDB::ExitCodes::INVALID_ARG, $logfile
        );
        print STDERR $errorMessage;
        exit $NeuroDB::ExitCodes::INVALID_ARG;
    } else {
        my %row          = $sth->fetchrow_hashref();
        $is_valid        = $row{isTarchiveValidated};
        $upload_id       = $row{UploadID};
    }

    # load the DICOM archive information from the tarchive table in studyInfo object
    %studyInfo = $utility->createTarchiveArray(
        $ArchiveLocation, $globArchiveLocation
    );
}

if ((!defined $is_valid || $is_valid == 0) && !$force) {
    $message = "\n ERROR: The validation has failed. Either run the validation again"
               . "and fix the problem or use -force to force the insertion.\n\n";
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::INVALID_TARCHIVE, $logfile
    );
    $notifier->spool('tarchive validation', $message, 0,
                    'minc_insertion.pl', $upload_id, 'Y',
                    $notify_notsummary);
    exit $NeuroDB::ExitCodes::INVALID_TARCHIVE;
}




# Create the MINC file object and maps DICOM fields
my $file = $utility->loadAndCreateObjectFile($minc, $upload_id);


# filters out parameters of length > NeuroDB::File::MAX_DICOM_PARAMETER_LENGTH
$message = "\n--> filters out parameters of length > "
           . NeuroDB::File::MAX_DICOM_PARAMETER_LENGTH . " for $minc\n";
print LOG $message if $verbose;
$file->filterParameters();




# If studyInfo is not defined (a.k.a. no uploadID or tarchiveID associated with
# this MINC file), verify that the seriesUID of the MINC file we want to insert is
# not present in the tarchive_series table. If it is, then exit with proper message.
if (!%studyInfo) {
    my $seriesUID = $file->getParameter('series_instance_uid');
    my $echo_time = $file->getParameter('acquisition:echo_time') * 1000;
    (my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT
      ArchiveLocation
    FROM
      tarchive
    WHERE
      TarchiveID = (
                     SELECT TarchiveID
                     FROM tarchive_series
                     WHERE SeriesUID=? AND EchoTime=?
                   )
QUERY
    print $query if $verbose;
    my $sth = $dbh->prepare($query);
    $sth->execute($seriesUID, $echo_time);
    my @array        = $sth->fetchrow_array;
    my $archiveLocation = $array[0];

    if ($archiveLocation) {
        $message = "\nERROR: found a DICOM archive containing DICOMs with the same "
                   . "SeriesUID ('$seriesUID') as the one present in the MINC file. "
                   . "The DICOM archive location containing those DICOM files is "
                   . "'$archiveLocation'. Please rerun the minc_insertion.pl "
                   . "with either -tarchivePath or -uploadID option.\n\n";
        $utility->writeErrorLog(
            $message, $NeuroDB::ExitCodes::INVALID_ARG, $logfile
        );
        $notifier->spool(
            'tarchive validation', $message,   0,
            'minc_insertion.pl',   $upload_id, 'Y',
            $notify_notsummary
        );
        exit $NeuroDB::ExitCodes::INVALID_ARG;
    }
}



# Grep information from the MINC header if not available in the studyInfo hash
$studyInfo{'PatientName'}            //= $file->getParameter('patient:full_name');
$studyInfo{'PatientID'}              //= $file->getParameter('patient:identification');
$studyInfo{'ScannerManufacturer'}    //= $file->getParameter('study:manufacturer');
$studyInfo{'ScannerModel'}           //= $file->getParameter('study:device_model');
$studyInfo{'ScannerSerialNumber'}    //= $file->getParameter('study:serial_no');
$studyInfo{'ScannerSoftwareVersion'} //= $file->getParameter('study:software_version');
$studyInfo{'DateAcquired'}           //= $file->getParameter('study:start_date');




## Determine PSC, ScannerID and Subject IDs
my ($center_name, $centerID) = $utility->determinePSC(\%studyInfo, 0, $upload_id);
my $scannerID = $utility->determineScannerID(
    \%studyInfo, 0, $centerID, $NewScanner, $upload_id
);
my $subjectIDsref = $utility->determineSubjectID(
    $scannerID, \%studyInfo, 0, $upload_id
);





## Validate that the candidate exists and that PSCID matches CandID
my $CandMismatchError = $utility->validateCandidate($subjectIDsref);

if (defined($CandMismatchError)) {
    $message = "\nCandidate Mismatch Error is $CandMismatchError\n";
    print LOG $message;
    print LOG " -> WARNING: This candidate was invalid. Logging to
              MRICandidateErrors table with reason $CandMismatchError";

    my $logQuery = "INSERT INTO MRICandidateErrors".
        "(SeriesUID, TarchiveID, MincFile, PatientName, Reason) ".
        "VALUES (?, ?, ?, ?, ?)";
    my $candlogSth = $dbh->prepare($logQuery);
    $candlogSth->execute(
        $file->getParameter('series_instance_uid'),
        $studyInfo{'TarchiveID'},
        NeuroDB::MRI::get_trashbin_file_rel_path($minc),
        $studyInfo{'PatientName'},
        $CandMismatchError
    );

    $notifier->spool('tarchive validation', $message, 0,
        'minc_insertion.pl', $upload_id, 'Y',
        $notify_notsummary);

    exit $NeuroDB::ExitCodes::CANDIDATE_MISMATCH;
}




################################################################
####### Get the $sessionID and $requiresStaging ################
################################################################
my ($sessionID, $requiresStaging) =
    NeuroDB::MRI::getSessionID( 
        $subjectIDsref, 
        $studyInfo{'DateAcquired'},
        \$dbh, $subjectIDsref->{'subprojectID'}
   );


################################################################
############ Compute the md5 hash ##############################
################################################################
my $not_unique_message = $utility->is_file_unique( $file, $upload_id );
if ($not_unique_message) {
    print STDERR $not_unique_message if $verbose;
    print LOG $not_unique_message;
    $notifier->spool(
        'tarchive validation', $not_unique_message, 0,
        'minc_insertion.pl',   $upload_id,          'Y',
        $notify_notsummary
    );
    exit $NeuroDB::ExitCodes::FILE_NOT_UNIQUE;
} 

################################################################
## at this point things will appear in the database ############
## Set some file information ###################################
################################################################
my $caveat = $acquisitionProtocol ? 1 : 0;
$file->setFileData( 'Caveat',          $caveat                                    );
$file->setFileData( 'ScannerID',       $scannerID                                 );
$file->setFileData( 'SessionID',       $sessionID                                 );
$file->setFileData( 'SeriesUID',       $file->getParameter('series_instance_uid') );
$file->setFileData( 'EchoTime',        $file->getParameter('echo_time')           );
$file->setFileData( 'PendingStaging',  $requiresStaging                           );
$file->setFileData( 'CoordinateSpace', 'native'                                   );
$file->setFileData( 'OutputType',      'native'                                   );
$file->setFileData( 'FileType',        'mnc'                                      );
$file->setFileData( 'TarchiveSource',  $studyInfo{'TarchiveID'}                   );

################################################################
## Get acquisition protocol (identify the volume) ##############
################################################################
($acquisitionProtocol, $acquisitionProtocolID, $extra_validation_status)
  = $utility->getAcquisitionProtocol(
      $file,
      $subjectIDsref,
      \%studyInfo,
      $center_name,
      $minc,
      $acquisitionProtocol,
      $bypass_extra_file_checks,
      $upload_id
    );


if($acquisitionProtocol =~ /unknown/) {
   $message = "\n  --> The minc file cannot be registered ".
              "since the AcquisitionProtocol is unknown \n";

   print LOG $message;
   $notifier->spool('minc insertion', $message, 0,
                   'minc_insertion.pl', $upload_id, 'Y', 
                   $notify_notsummary);
   exit $NeuroDB::ExitCodes::UNKNOWN_PROTOCOL;
}

################################################################
# Register scans into the database.  Which protocols ###########
# to keep optionally controlled by the config file #############
################################################################

my $acquisitionProtocolIDFromProd = $utility->registerScanIntoDB(
    \$file,               \%studyInfo,    $subjectIDsref,
    $acquisitionProtocol, $minc,          $extra_validation_status,
    $reckless,            $sessionID,     $upload_id
);

# if the scan was inserted into the files table and there is an
# extra_validation_status set to 'warning', update the mri_violations_log table
# MincFile field with the path of the file in the assembly directory
if (defined $acquisitionProtocolIDFromProd && $extra_validation_status eq 'warning') {
    $utility->update_mri_violations_log_MincFile_path($file);
}

if ((!defined$acquisitionProtocolIDFromProd)
   && (defined(&Settings::isFileToBeRegisteredGivenProtocol))
   ) {
   $message = "\n  --> The minc file cannot be registered ".
                "since $acquisitionProtocol ".
                "does not exist in $profile ". 
                "or it did not pass the extra_file_checks\n";
   print LOG $message;
   $notifier->spool('minc insertion', $message, 0,
                   'minc_insertion', $upload_id, 'Y',
                   $notify_notsummary);
    exit $NeuroDB::ExitCodes::PROJECT_CUSTOMIZATION_FAILURE;
}
################################################################
### Add series notification ####################################
################################################################
$message = sprintf(
    "\n CandID: %s, PSCID: %s, Visit: %s, Acquisition Date: %s, Series Description %s\n",
    $subjectIDsref->{'CandID'},
    $subjectIDsref->{'PSCID'},
    $subjectIDsref->{'visitLabel'},
    (defined $file->getParameter('acquisition_date')
        ? $file->getParameter('acquisition_date') : 'UNKNOWN'),
    (defined $file->getParameter('series_description')
        ? $file->getParameter('series_description') : 'UNKNOWN')
);
$notifier->spool('mri new series', $message, 0,
            'minc_insertion.pl', $upload_id, 'N', 
        $notify_detailed);

if ($verbose) {
    print "\nFinished file:  ".$file->getFileDatum('File')." \n";
}

################################################################
###################### Creation of NIfTIs ######################
################################################################
if ($create_nii) {
    print "\nCreating NIfTI files\n" if $verbose;
    NeuroDB::MRI::make_nii(\$file, $data_dir);
}

################################################################
################# Create minc-pics #############################
################################################################
if ($create_minc_pics) {
    print "\nCreating Minc Pics\n" if $verbose;
    NeuroDB::MRI::make_pics(
        \$file, $data_dir, "$data_dir/pic", $horizontalPics
    );
}

################################################################
################## Succesfully completed #######################
################################################################
exit $NeuroDB::ExitCodes::SUCCESS;


=pod

=head3 logHeader()

Function that adds a header with relevant information to the log file.

=cut

sub logHeader () {
    print LOG "
----------------------------------------------------------------
            AUTOMATED DICOM DATA UPLOAD
----------------------------------------------------------------
*** Date and time of upload    : $date
*** Location of source data    : $source_data_for_log
*** tmp dir location           : $TmpDir
*** Upload ID of source data   : $upload_id_for_log
";
}


__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut

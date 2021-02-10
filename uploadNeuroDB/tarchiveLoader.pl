#! /usr/bin/perl
# $Id: tarchiveLoader.pl,v 1.24 2007/12/18 16:00:21 sebas Exp $

=pod

=head1 NAME

tarchiveLoader.pl -- this script performs the following:

- validation of the DICOM archive

- conversion of DICOM datasets into MINC files

- automated protocol checks against the entries in the C<mri_protocol> and
optionally, C<mri_protocol_checks> tables.


=head1 SYNOPSIS

perl uploadNeuroDB/tarchiveLoader.pl </path/to/DICOM-tarchive> C<[options]>


Available options are:

-profile                 : Name of the config file in C<../dicom-archive/.loris_mri>

-uploadID                : UploadID associated to this upload

-force                   : Force the script to run even if the validation
                           has failed

-reckless                : Upload data to database even if study protocol is
                           not defined or violated

-keeptmp                 : Keep temporary directory. Make sense if have
                           infinite space on your server

-xlog                    : Open an xterm with a tail on the current log file

-verbose                 : If set, be verbose

-seriesuid               : Only insert this C<SeriesUID>

-acquisition_protocol    : Suggest the acquisition protocol to use

-bypass_extra_file_checks: Bypass C<extra_file_checks>


=head1 DESCRIPTION


This script interacts with the LORIS database system. It will fetch or modify
contents of the following tables:
C<session>, C<parameter_file>, C<parameter_type>, C<parameter_type_category>,
C<files>, C<mri_staging>, C<notification_spool>, C<mri_scanner>



=head2 Methods

=cut


use strict;
use warnings;
no warnings 'once';
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

use NeuroDB::Database;
use NeuroDB::DatabaseException;

use NeuroDB::objectBroker::ObjectBrokerException;
use NeuroDB::objectBroker::ConfigOB;



# Turn on autoflush for standard output buffer so that we immediately see 
#the results of print statements.
$|++;

## Starting the program
my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.24 $ 
=~ /: (\d+)\.(\d+)/;
## needed for log and template
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) 
    =localtime(time);
my $date        = sprintf(
                    "%4d-%02d-%02d %02d:%02d:%02d",
                     $year+1900,$mon+1,$mday,$hour,$min,$sec
                  );
my $debug       = 0;  
my $message     = '';
my $upload_id;
my $verbose     = 0;           # default, overwritten if the scripts are run with -verbose
my $notify_detailed   = 'Y';   # notification_spool message flag for messages to be displayed 
                               # with DETAILED OPTION in the front-end/imaging_uploader 
my $notify_notsummary = 'N';   # notification_spool message flag for messages to be displayed 
                               # with SUMMARY Option in the front-end/imaging_uploader 
my $profile     = undef;       # this should never be set unless you are in a
                               # stable production environment
my $reckless    = 0;           # this is only for playing and testing. Don't 
                               #set it to 1!!!
my $force       = 0;           # This is a flag to force the script to run  
                               # Even if the validation has failed
my $xlog        = 0;           # default should be 0
my $valid_study = 0;
my $newTarchiveLocation = undef;
my $seriesuid   = undef;       # if you want to insert a specific SeriesUID
my $bypass_extra_file_checks=0;# If you need to bypass the extra_file_checks,
                               # set to 1.
my $acquisitionProtocol;       # Specify the acquisition Protocol also bypasses
                               # the checks
my @opt_table = (
                 ["Basic options","section"],
                 ["-profile     ","string",1, \$profile,
                  "Name of config file in ../dicom-archive/.loris_mri"
                 ],
                 ["-uploadID", "string", 1, \$upload_id, "UploadID associated to ".
                 "this upload."],
                 ["-force", "boolean", 1, \$force,"Force the script to run ".
                 "even if the validation has failed."],
                 ["Advanced options","section"],
                 ["-reckless", "boolean", 1, \$reckless,"Upload data to ".
                  "database even if study protocol is not defined or violated."
                 ],
                 ["Fancy options","section"],
# fixme		 ["-keeptmp", "boolean", 1, \$keep, "Keep temporay directory. Make
# sense if have infinite space on your server."],
                 ["-xlog", "boolean", 1, \$xlog,"Open an xterm with a tail on".
                  "the current log file."
                 ],
                 ["General options", "section"],
                 ["-verbose", "boolean", 1,   \$verbose, "Be verbose."],
                 ["-seriesuid", "string", 1, \$seriesuid, "Only insert this SeriesUID"],
                 ["-acquisition_protocol","string", 1, \$acquisitionProtocol,
                  "Suggest the acquisition protocol to use."],
                 ["-bypass_extra_file_checks", "boolean", 1, \$bypass_extra_file_checks,
                  "Bypass extra_file_checks."],
                 );

my $Help = <<HELP;
******************************************************************************
TARCHIVE LOADER 
******************************************************************************

Author  :   J-Sebastian Muehlboeck based on Jonathan Harlap\'s process_uploads 
            using the all singing and dancing (eierlegende Wollmilchsau) 
            NeuroDB lib
Date    :   2006/12/20
Version :   $versionInfo

This takes a [dicom{T(ar}]chive) as an argument and 
performs a lot of magic on the acquisitions within it.  

- archive verification
- candidate id extraction and/or neurodb candidate creation
- study site determination
- scanner identity check  
- dicom to minc conversion
- miscellaneous header data extraction
- file relocation (to the MRI repository)
- neuroDB mri database registration

Documentation: perldoc tarchiveLoader.pl

HELP

my $Usage = <<USAGE;
usage: $0 </path/to/DICOM-tarchive> [options]
       $0 -help to list options

USAGE
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

################################################################
################### input option error checking ################
################################################################
if ( !$profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
if ( !$upload_id ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -uploadID argument\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}
if ( !$ARGV[0] ) {
    print $Help; 
    print STDERR "$Usage\n\tERROR: You must specify a valid tarchive.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}



# ----------------------------------------------------------------
## Establish database connection
# ----------------------------------------------------------------

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

$message = "\n==> Successfully connected to database \n";


# ----------------------------------------------------------------
## Get config settings using ConfigOB
# ----------------------------------------------------------------

my $configOB = NeuroDB::objectBroker::ConfigOB->new(db => $db);

my $data_dir       = $configOB->getDataDirPath();
my $tarchivePath   = $configOB->getTarchiveLibraryDir();
my $mail_user      = $configOB->getMailUser();
my $get_dicom_info = $configOB->getDicomInfo();
my $converter      = $configOB->getConverter();


# -----------------------------------------------------------------
## Get config setting using the old database calls
# -----------------------------------------------------------------

my $exclude = NeuroDB::DBI::getConfigSetting(\$dbh, 'excluded_series_description');



my $tarchive = $ARGV[0];
unless ($tarchive =~ m/$tarchivePath/i) {
    $tarchive = ($tarchivePath . "/" . $tarchive);
}

unless (-e $tarchive) {
    print STDERR "\nERROR: Could not find archive $tarchive.\n"
        . "Please, make sure the path to the archive is correct.\n\n";
    exit $NeuroDB::ExitCodes::INVALID_PATH;
}

################################################################
#### These settings are in the database, & are     #############
#### accessible through the Configuration Module   #############
################################################################
my $pic_dir = $data_dir.'/pic';

my $template       = "TarLoad-$hour-$min-XXXXXX"; # for tempdir
my $User           = getpwuid($>);

# fixme there are better ways 
my @progs = ("convert", "Mincinfo_wrapper.pl", "mincpik.pl", $converter);
# create the temp dir
my $TmpDir = tempdir(
                 $template, TMPDIR => 1, CLEANUP => 1 
             );
# create logdir(if !exists) and logfile
my @temp     = split(/\//, $TmpDir); 
my $templog  = $temp[$#temp];
my $LogDir   = "$data_dir/logs"; 
if (!-d $LogDir) { 
    mkdir($LogDir, 0770); 
}
my $logfile  = "$LogDir/$templog.log";
open LOG, ">$logfile";
LOG->autoflush(1);
&logHeader();

print LOG $message;

################################################################
############### If xlog is set, fork a tail on log file. #######
################################################################
my $childPID; 
if ($xlog) { 
    $childPID = fork(); 
    if ($childPID == 0) {
        my $command = "xterm -geometry 130x70 -e tail -f $logfile";
        exec($command) or die "Command $command failed: $!\n";
    }
}

################################################################
# get useful information from the tarchive table  - The regex is
# very study specific... !!!!!! fixme
# Fixme figure out a way to get rid of study specific ways of
# extracting information ... if there is
# This will query the tarchive and retrieve (hopefully) enough
# information to continue the upload.
# fixme documentation needed
################################################################

################################################################
################## Instantiate MRIProcessingUtility ############
################################################################
my $utility = NeuroDB::MRIProcessingUtility->new(
                  $db, \$dbh, $debug, $TmpDir, $logfile, $verbose, $profile
              );

################################################################
################ Register programs #############################
################################################################
$utility->registerProgs(@progs);

################################################################
##### make the notifier object #################################
################################################################
my $notifier = NeuroDB::Notify->new(\$dbh);

################################################################
################ Construct the tarchiveInfo Array ##############
################################################################
my $ArchiveLocation    = $tarchive;
$ArchiveLocation       =~ s/$tarchivePath\/?//g;
my %tarchiveInfo = $utility->createTarchiveArray($ArchiveLocation);

################################################################
################## Call the validation script ##################
################################################################
my $script = sprintf(
    "tarchive_validation.pl %s -profile %s -uploadID %s",
    quotemeta($tarchive),
    quotemeta($profile),
    quotemeta($upload_id)
);
$script .= " -verbose " if ($verbose);

################################################################
###### Note: system call returns the process ID ################
###### To the actual exit value, shift right by ################
###### eight as done below #####################################
################################################################
my $output = system($script); 
$output = $output >> 8;

################################################################
#############Exit if the is_valid is false and $force is not####
################################################################
if (($output != 0)  && ($force==0)) {
 $message = "\n ERROR: The validation has failed. Either re-run the ".
            "validation again and fix the problem. Or re-run ".
            "tarchiveLoader.pl using -force to force the execution.\n\n";
 $utility->writeErrorLog(
     $message, $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE, $logfile
 );
 $notifier->spool('tarchive validation', $message, 0, 
		'tarchiveLoader.pl', $upload_id, 'Y',
		$notify_notsummary);
 exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
}

################################################################
########## Get the $center_name, $centerID ################
################################################################
my ($center_name, $centerID) =
     $utility->determinePSC(\%tarchiveInfo, 0, $upload_id);

################################################################
######### Determine the ScannerID ##############################
################################################################
my $scannerID = $utility->determineScannerID(
        \%tarchiveInfo, 0, $centerID, $upload_id
);

################################################################
###### Construct the $subjectIDsref array ######################
################################################################
my ($subjectIDsref) = $utility->determineSubjectID(
    $scannerID, \%tarchiveInfo, 0, $upload_id, $User, $centerID
);

################################################################
###### Extract the tarchive and feed the dicom data ############
###### Dir to the uploader #####################################
################################################################
my ($ExtractSuffix,$study_dir,$header) = 
    $utility->extractAndParseTarchive($tarchive, $upload_id, $seriesuid);


################################################################
##################### convert the dicom data to minc ###########
################################################################
$utility->dicom_to_minc(
    $study_dir, $converter, $get_dicom_info, $exclude, $mail_user, $upload_id
);


################################################################
############### get a list of mincs ############################
################################################################
my @minc_files = ();
$utility->get_mincs(\@minc_files, $upload_id);
my $mcount = $#minc_files + 1;
$message = "\nNumber of MINC files that will be considered for inserting ".
      "into the database: $mcount\n";
$notifier->spool('tarchive loader', $message, 0,
		'tarchiveLoader.pl', $upload_id, 'N',
		$notify_detailed);
if ($verbose){
    print $message;
}
################################################################
# If no good data was found stop processing and write error log.
################################################################
if ($mcount < 1) {
    $message = "\nNo data could be converted into valid MINC files.\n";
    if ($exclude && ref($exclude) eq 'ARRAY') {
        my $excluded_series = join(', ', map {quotemeta($_)} @$exclude);
        $message .= "$excluded_series will not be considered! \n" ;
    } elsif ($exclude) {
        $message .= "$exclude will not be considered! \n";
    }
    $utility->writeErrorLog(
        $message, $NeuroDB::ExitCodes::NO_VALID_MINC_CREATED, $logfile
    );
    $notifier->spool('tarchive loader', $message, 0,
		    'tarchiveLoader.pl', $upload_id, 'Y',
		    $notify_notsummary);
    exit $NeuroDB::ExitCodes::NO_VALID_MINC_CREATED;
}

################################################################
#################### LOOP through MINCs ########################
# At this step we actually have (multiple) MINC files so we loop
# a valid study has at least one file that can be uploaded #####
################################################################
my $minc_inserted = 0;
foreach my $minc (@minc_files) {

    ############################################################
    # if the tarchive has not been moved yet ###################
    # ($valid_study undefined)-> move the tarchive from the ####
    # inbox into the tarchive library ##########################
    ############################################################
    if ((!defined($tarchivePath)) || 
        (defined($tarchivePath) &&    
        ($tarchive =~ m/$tarchivePath\/\d\d\d\d\//i))) { 
            $newTarchiveLocation = $tarchive; 
    }
    elsif (!$valid_study) {
        $newTarchiveLocation = 
            $utility->moveAndUpdateTarchive(
                $tarchive, \%tarchiveInfo, $upload_id
            );
    }
    $tarchive = $newTarchiveLocation;

    ###########################################################
    ############# Call the minc_insertion script ##############
    ###########################################################
    $script = sprintf(
        "minc_insertion.pl -mincPath %s -profile %s -uploadID %s",
        quotemeta($minc),
        quotemeta($profile),
        quotemeta($upload_id)
    );
    $script .= " -force"                    if $force;
    $script .= " -verbose"                  if $verbose;
    $script .= " -bypass_extra_file_checks" if $bypass_extra_file_checks;
    if ($acquisitionProtocol) {
        $script .= " -acquisition_protocol " . quotemeta($acquisitionProtocol);
    }

    print $script . "\n" if $debug;
    $output = system($script); # system call returns the process ID
    $output = $output >> 8;    # to get actual exit value, need to shift right by 8
    if ($output==0) {
        # if the script's return code = 0, mark the study as valid as at least
        # one MINC file was inserted into the DB
        $minc_inserted++;
        $valid_study = 1;
    }

} # end foreach $minc

################################################################
############### Compute SNR on 3D modalities ###################
################################################################
$utility->computeSNR($tarchiveInfo{TarchiveID}, $upload_id);
################################################################
####### Add order of acquisition for similar modalities ########
####### within the same session based on series number #########
################################################################
$utility->orderModalitiesByAcq($tarchiveInfo{TarchiveID}, $upload_id);


if ($valid_study) {

    ############################################################
    ### Update the number_of_mincCreated #######################
    ### And number_of_mincInserted #############################
    ############################################################

    my $query = "SELECT number_of_mincInserted FROM mri_upload WHERE UploadID=?";
    print $query . "\n" if $debug;

    my $sth = $dbh->prepare($query);
    $sth->execute($upload_id);
    my $oldCount = $sth->fetchrow_hashref->{'number_of_mincInserted'};
    my $newCount = $minc_inserted + ($oldCount ? $oldCount : 0);

    $query = "UPDATE mri_upload "
             . " SET number_of_mincInserted=?, number_of_mincCreated=? "
             . " WHERE UploadID=?";
    print $query . "\n" if $debug;

    my $mri_upload_update = $dbh->prepare($query);
    $mri_upload_update->execute($newCount, $mcount, $upload_id);
 
    ############################################################
    ############# Create minc-pics #############################
    ############################################################
    print "\nCreating Minc Pics\n" if $verbose;
    NeuroDB::MRI::make_minc_pics(\$dbh,
                                  $tarchiveInfo{TarchiveID},
                                  $profile,
                                  0, # minFileID $row[0], maxFileID $row[1]
                                  $debug, 
                                  $verbose);
    
    ############################################################
    # spool a new study message ################################
    ############################################################
    $message = sprintf(
        "\n CandID: %s, PSCID: %s, Visit: %s, Acquisition Date: %s\n",
        $subjectIDsref->{'CandID'},
        $subjectIDsref->{'PSCID'},
        $subjectIDsref->{'visitLabel'},
        $tarchiveInfo{'DateAcquired'} // 'UNKNOWN'
    );
    $notifier->spool('mri new study', $message, 0,
		    'tarchiveLoader.pl', $upload_id, 'N',
		    $notify_detailed);

    ############################################################
    #### link the tarchive and mri_upload table  with session ##
    ############################################################
    my ($sessionRef, $errMsg) = NeuroDB::MRI::getSessionInformation(
        $subjectIDsref, $tarchiveInfo{'DateAcquired'}, $dbh, $db
    );

    # Session cannot be retrieved from the DB and, if createVisitLabel is set to
    # 1, creation of a new session failed
    if (!$sessionRef) {
        print STDERR $errMsg if $verbose;
        print LOG $errMsg;
        $notifier->spool(
            'session validation/creation', "$errMsg. tarchiveloader.pl failed", 0,
            'tarchiveLoader.pl',  $upload_id, 'Y',
            $notify_notsummary
        );
        exit ($subjectIDsref->{'createVisitLabel'} == 1
            ? $NeuroDB::ExitCodes::CREATE_SESSION_FAILURE
            : $NeuroDB::ExitCodes::GET_SESSION_ID_FAILURE);
    }
     
    $query = "UPDATE tarchive SET SessionID=? WHERE TarchiveID=?";
    $sth   = $dbh->prepare($query);
    print $query . "\n" if $debug;
    $sth->execute($sessionRef->{'ID'}, $tarchiveInfo{'TarchiveID'});

    $query = "UPDATE mri_upload SET SessionID=? WHERE UploadID=?";
    $sth   = $dbh->prepare($query);
    print $query . "\n" if $debug;
    $sth->execute($sessionRef->{'ID'}, $upload_id);

} else {
    ############################################################
    ## spool a failure message This has been changed to tarchive
    ## instead of using patientName ############################
    ############################################################
    $message = sprintf(
        "\n %s acquired %s was deemed invalid\n\n%s\n",
        $tarchive,
        $tarchiveInfo{'DateAcquired'} // 'UNKNOWN',
        $study_dir
    );
    $notifier->spool('mri invalid study', $message, 0,
		    'tarchiveLoader.pl', $upload_id, 'Y',
		    $notify_notsummary);
}

################################################################
# make final logfile name without overwriting phantom logs #####
################################################################
my $final_logfile = $center_name;
unless ($tarchiveInfo{'DateAcquired'} && $subjectIDsref->{'CandID'}) {
    ### if something went wrong and there is no acq date or CandID
    $final_logfile .= '_'.$temp[$#temp];
} else {
    $final_logfile .= $subjectIDsref->{'PSCID'} if $subjectIDsref->{'isPhantom'};
    $final_logfile .= $tarchiveInfo{'DateAcquired'};
    $final_logfile .= $subjectIDsref->{'CandID'};
}
$final_logfile .= '.log.gz';

################################################################
# fixme for now we assume that extracted data will not be kept #
################################################################
my $cleanup = "rm -rf ${TmpDir}/${ExtractSuffix}*";
$message = "\nCleaning up temp files: $cleanup\n";
print $message if $verbose;
`$cleanup`;

################################################################
## if there are leftovers, dump them in the trashbin ###########
################################################################
my @leftovers = `\\ls -1 $TmpDir`;

if (scalar(@leftovers) > 0) {
    my $trashdir = $data_dir . '/trashbin/' . $temp[$#temp];
    $message = "\n==> LEFTOVERS: ".scalar(@leftovers).
    "\n --> Moving leftovers to $trashdir\n";
    $notifier->spool('tarchive loader', $message, 0,
		    'tarchiveLoader.pl', $upload_id, 'Y',
		    $notify_notsummary);
    print LOG $message;
    `mkdir -p -m 770 $trashdir`;
    `chmod -R u+w $TmpDir/*`;
    `mv $TmpDir/* $trashdir`;
    open MAIL, "| mail $mail_user";
    print MAIL "Subject: [URGENT Automated] upload NeuroDB leftovers!\n";
    print MAIL "Moved some leftovers to $trashdir\n";
    print MAIL "Log of process in $data_dir/logs/$final_logfile\n";
    print MAIL "Files left over:\n".join("", @leftovers)."\n";
    close MAIL;
}
$message ="\n==> Done tarchiveLoader.pl execution!  Removing $TmpDir.\n";
$notifier->spool('tarchive loader', $message, 0,
		'tarchiveLoader.pl', $upload_id, 'N',
		$notify_detailed);
print LOG $message;
close LOG;
`gzip -9 $logfile`;
my $cmd = "mv $logfile.gz $data_dir/logs/$final_logfile";
`$cmd`;
################################################################
############# kill the xterm with the tail on log ##############
################################################################
if ($xlog) {
    `kill -9 $childPID`;
}
################################################################
############# if no mincs are inserted or the valid_study is ###
############## false, the exit code will not be 0 ##############
################################################################

if (!$valid_study) {
    $message =  "\n No Mincs inserted \n \n";
    print STDERR ($message);
    $notifier->spool('mri invalid study', $message, 0,
		    'tarchiveLoader.pl', $upload_id, 'Y',
		    $notify_notsummary);
    exit $NeuroDB::ExitCodes::INSERT_FAILURE;
}

###############################################################
### Set Processed to 1 in mri_upload table#####################
###############################################################
my $query = "UPDATE mri_upload SET InsertionComplete=1 WHERE UploadID=?";

my $mri_upload_update = $dbh->prepare($query);
$mri_upload_update->execute($upload_id);

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
    *** Location of source data    : $tarchive
    *** tmp dir location           : $TmpDir
    ";
}



__END__

=pod

=head1 TO DO

- dicom_to_minc: change converter back to perl (or make configurable)

- add a check for all programms that will be used (exists, but could
  be better....)

- consider whether to add a check for registered protocols against the
  tarchive db to save a few minutes of converting

- also add an option to make it interactively query user to learn new protocols

- add to config file whether or not to autocreate scanners

- fix comments written as #fixme in the code

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

J-Sebastian Muehlboeck based on Jonathan Harlap\'s process_uploads, LORIS
community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut

package NeuroDB::MRIProcessingUtility;


=pod

=head1 NAME

NeuroDB::MRIProcessingUtility -- Provides an interface for MRI processing
utilities

=head1 SYNOPSIS

  use NeuroDB::ProcessingUtility;

  my $utility       = NeuroDB::MRIProcessingUtility->new(
                        $db, \$dbh,    $debug,  $TmpDir,
                        $logfile, $LogDir, $verbose
                      );

  %tarchiveInfo     = $utility->createTarchiveArray($ArchiveLocation);

  my ($center_name, $centerID) = $utility->determinePSC(\%tarchiveInfo,0);

  my $projectID     = $utility->determineProjectID(\%tarchiveInfo);
  my $scannerID     = $utility->determineScannerID(\%tarchiveInfo, 0, $centerID, $projectID);

  my $subjectIDsref = $utility->determineSubjectID(
                        $scannerID,
                        \%tarchiveInfo,
                        0
                      );

  my $CandMismatchError = $utility->validateCandidate(
                            $subjectIDsref
                          );

  $utility->computeSNR($TarchiveID, $ArchLoc);
  $utility->orderModalitiesByAcq($TarchiveID, $ArchLoc);

=head1 DESCRIPTION

Mishmash of MRI processing utility functions used mainly by the insertion
scripts of LORIS.

=head2 Methods

=cut


use English;
use Carp;
use strict;
use warnings;
no warnings 'once';
use Data::Dumper;
use File::Basename;

use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::Notify;
use NeuroDB::ExitCodes;

use NeuroDB::Database;
use NeuroDB::DatabaseException;

use NeuroDB::objectBroker::ObjectBrokerException;
use NeuroDB::objectBroker::MriViolationsLogOB;
use NeuroDB::objectBroker::ConfigOB;
use NeuroDB::objectBroker::TarchiveOB;
use NeuroDB::objectBroker::MriUploadOB;


use Path::Class;
use Scalar::Util qw(blessed);
use DateTime;
use Time::Piece;

## Define Constants ##
my $notify_detailed   = 'Y'; # notification_spool message flag for messages to be displayed
                             # with DETAILED OPTION in the front-end/imaging_uploader
my $notify_notsummary = 'N'; # notification_spool message flag for messages to be displayed
                             # with SUMMARY Option in the front-end/imaging_uploader


=pod

=head3 new($db, $dbhr, $debug, $TmpDir, $logfile, $verbose, $profile) >> (constructor)

Creates a new instance of this class. The parameter C<$dbhr> is a reference
to a C<DBI> database handle, used to set the object's database handle, so that
all the DB-driven methods will work.

INPUT:
  - $db      : database object
  - $dbhr    : DBI database handle reference
  - $debug   : degug flag (1 for debug, 0 otherwise)
  - $TmpDir  : temporay directory name (for tarchive extraction)
  - $logfile : log file name
  - $verbose : boolean flag for verbose behavior (1 lots of messages, 0 otherwise)
  - $profile : path of the profile file

RETURNS: new instance of this class.

=cut

sub new {
    my $params = shift;
    my ($db, $dbhr, $debug, $TmpDir, $logfile, $verbose, $profile) = @_;
    unless(defined $dbhr) {
       croak(
           "Usage: ".$params."->new(\$databaseHandleReference)"
       );
    }

    unless(defined $db && blessed($db) && $db->isa('NeuroDB::Database')) {
        croak(
           "Usage: ".$params."->new(\$databaseObject)"
        );
    }
    my $self = {};

    ############################################################
    ############### Create a settings package ##################
    ############################################################
    {
     package Settings;
     do "$ENV{LORIS_CONFIG}/.loris_mri/$profile";
    }

    # ----------------------------------------------------------
    ## Create the ConfigOB
    # ----------------------------------------------------------
    my $configOB = NeuroDB::objectBroker::ConfigOB->new(db => $db);


    ############################################################
    #### Create the log file and a Notify Object################
    ############################################################
    my $LogDir    = dirname($logfile);
    my $file_name = basename($logfile);
    my $dir       = dir($LogDir);
    my $file      = $dir->file($file_name);
    my $LOG       = $file->openw();
    my $Notify    = NeuroDB::Notify->new( $dbhr );
    $LOG->autoflush(1);

    $self->{'Notify'}   = $Notify;
    $self->{'LOG'}      = $LOG;
    $self->{'verbose'}  = $verbose;
    $self->{'LogDir'}   = $LogDir;
    $self->{'dbhr'}     = $dbhr;
    $self->{'debug'}    = $debug;
    $self->{'TmpDir'}   = $TmpDir;
    $self->{'logfile'}  = $logfile;
    $self->{'db'}       = $db;
    $self->{'configOB'} = $configOB;

    return bless $self, $params;
}


=pod

=head3 writeErrorLog($message, $failStatus, $LogDir)

Writes error log. This is a useful function that will close the log and write
error messages in case of abnormal program termination.

INPUTS:
  - $message   : notification message
  - $failStatus: fail status of the process
  - $LogDir    : log directory

=cut

sub writeErrorLog {
    my $this = shift;
    my ($message, $failStatus, $LogDir) = @_;
    print STDERR $message;
    $this->{LOG}->print($message);
    $this->{LOG}->print(
        "program exit status: $failStatus"
    );
    `cat $this->{logfile}  >> $this->{LogDir}/error.log`;
    close $this->{LOG};
    `rm -f $this->{logfile} `;
}


=pod

=head3 lookupNextVisitLabel($CandID, $dbhr)

Will look up for the next visit label of candidate C<CandID>. Useful only if
the visit label IS NOT encoded somewhere in the patient ID or patient name.

INPUTS:
  - $CandID: candidate's C<CandID>
  - $dbhr  : database handle reference

RETURNS: next visit label found for the candidate

=cut

sub lookupNextVisitLabel {
    my $this = shift;
    my ($CandID, $dbhr) = @_;
    my $visitLabel = 1;
    my $query = "SELECT Visit_label FROM session".
                " WHERE CandID=$CandID AND Active='Y'".
                " ORDER BY ID DESC LIMIT 1";
    if ($this->{debug}) {
        print $query . "\n";
    }
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();
    if ($sth->rows > 0) {
        my @row = $sth->fetchrow_array();
        $visitLabel = $row[0] + 1;
    }
    return $visitLabel;
}


=pod

=head3 getDICOMFileNamesfromSeriesUID($seriesuid, @alltarfiles)

Will extract from the C<tarchive_files> table a list of DICOM files
matching a given C<SeriesUID>.

INPUTS:
  - $seriesUID  : C<SeriesUID> to use for matching
  - @alltarfiles: list of DICOM files matching the C<SeriesUID>

RETURNS: list of DICOM files corresponding to the C<SeriesUID>

=cut

sub getDICOMFileNamesfromSeriesUID {

    # longest common prefix
    sub LCP {
      return '' unless @_;
      my $prefix = shift;
      for (@_) {
          chop $prefix while (! /^\Q$prefix\E/);
          }
      return $prefix;
    }

    my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
    my ($seriesuid, @alltarfiles) = @_;
    my @filearray;
    my $tarstring = ' --wildcards ';
    my $query = "select tf.FileName from tarchive_files as tf".
        " where tf.TarchiveID = (select distinct ts.tarchiveID   from tarchive_series as ts where ts.SeriesUID=?)".
        " and tf.SeriesNumber = (select distinct ts.SeriesNumber from tarchive_series as ts where ts.SeriesUID=?)".
        " order by tf.FileNumber";
    my $sth = $dbh->prepare($query);
    $sth->execute($seriesuid, $seriesuid);
    while (my $tf = $sth->fetchrow_hashref()) {
        push @filearray, $tf->{'FileName'};
        $tarstring .= "'*" . $tf->{'FileName'} . "' ";
    }

    my $lcp = LCP(@alltarfiles);
    $tarstring =~ s/$lcp//g;

    return $tarstring;
}


=pod

=head3 extract_tarchive($tarchive, $upload_id, $seriesuid)

Extracts the DICOM archive so that data can actually be uploaded.

INPUTS:
  - $tarchive : path to the DICOM archive
  - $upload_id: upload ID of the study
  - $seriesuid: optionally a series UID

RETURNS: the extracted DICOM directory

=cut

sub extract_tarchive {
    my $this = shift;
    my ($tarchive, $upload_id, $seriesuid) = @_;
    my $message = '';
    my $tarnames = '';
    # get the upload_id from the tarchive source location
    # to pass to the notification_spool
    $message = "\nExtracting tarchive $tarchive in $this->{TmpDir} \n";
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    my $cmd = "cd $this->{TmpDir} ; tar -xf $tarchive";
    $message = "\n" . $cmd . "\n";
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    `$cmd`;
    opendir TMPDIR, $this->{TmpDir};
    my @tars = grep { /\.tar\.gz$/ && -f "$this->{TmpDir}/$_" }
        readdir(TMPDIR);
    closedir TMPDIR;

    if (scalar(@tars) != 1) {
        my $message = "Error: Could not find inner tar in $tarchive!\n";
        print STDERR $message;
        print @tars . "\n";
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);
        exit $NeuroDB::ExitCodes::EXTRACTION_FAILURE;
    }

    my $dcmtar = $tars[0];
    my $dcmdir = $dcmtar;
    $dcmdir =~ s/\.tar\.gz$//;

    if (defined($seriesuid)) {
        print "seriesuid: $seriesuid\n" if $this->{verbose};
        my @alltarfiles = `cd $this->{TmpDir} ; tar -tzf $dcmtar`;
        $tarnames = getDICOMFileNamesfromSeriesUID($seriesuid, @alltarfiles);
        print "tarnames: $tarnames\n" if $this->{verbose};
    }

    `cd $this->{TmpDir} ; tar -xzf $dcmtar $tarnames`;
    return $dcmdir;
}


=pod

=head3 extractAndParseTarchive($tarchive, $upload_id, $seriesuid)

Extracts and parses the DICOM archive.

INPUTS:
  - $tarchive : path to the DICOM archive
  - $upload_id: upload ID of the study
  - $seriesuid: optionally a series UID

RETURNS:
  - $ExtractSuffix: extract suffix
  - $study_dir    : extracted study directory
  - $header       : study meta data header

=cut

sub extractAndParseTarchive {

    my $this = shift;
    my ($tarchive, $upload_id, $seriesuid) = @_;

    my $study_dir = $this->{TmpDir}  . "/" .
        $this->extract_tarchive($tarchive, $upload_id, $seriesuid);
    my $ExtractSuffix  = basename($tarchive, ".tar");
    # get rid of the tarchive Prefix
    $ExtractSuffix =~ s/DCM_(\d{4}-\d{2}-\d{2})?_//;
    my $info       = "head -n 12 $this->{TmpDir}/${ExtractSuffix}.meta";
    my $header     = `$info`;
    my $message = "\n$header\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);

    return ($ExtractSuffix, $study_dir, $header);
}


=pod

=head3 determineSubjectID($scannerID, $tarchiveInfo, $to_log, $upload_id, $User, $centerID)

This function does:
1) Determine subject's ID based on scanner ID and DICOM archive information.
2) Call the C<CreateMRICandidate> function (will create the candidate if it does
not exists and C<createCandidates> config option is set to yes)
3) Call the C<validateCandidate> to validate the candidate information
(it will return a C<CandMismatchError> if there is one)

INPUTS:
  - $dbh         : database handle
  - $scannerID   : scanner ID,
  - $tarchiveInfo: DICOM archive information hash ref,
  - $to_log      : boolean if this step should be logged
  - $upload_id   : upload ID of the study
  - $User        : user running the insertion pipeline
  - $centerID    : center ID of the candidate

RETURNS: subject's ID hash ref containing C<CandID>, C<PSCID>, Visit Label,
ProjectID, CohortID and C<CandMismatchError> information

=cut

sub determineSubjectID {

    my $this = shift;
    my ($scannerID, $tarchiveInfo, $to_log, $upload_id, $User, $centerID) = @_;
    my $dbhr = $this->{dbhr};

    $to_log = 1 unless defined $to_log;
    if (!defined(&Settings::getSubjectIDs)) {
        if ($to_log) {
            my $message =  "\nERROR: Profile does not contain getSubjectIDs ".
                           "routine. Upload will exit now.\n\n";
            $this->writeErrorLog(
                $message, $NeuroDB::ExitCodes::PROJECT_CUSTOMIZATION_FAILURE
            );
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);
        exit $NeuroDB::ExitCodes::PROJECT_CUSTOMIZATION_FAILURE;
        }
    }

    # determine the PSCID, CandID and Visit label based on PatientName or PatientID
    my $patientID   = $tarchiveInfo->{'PatientID'};
    my $patientName = $tarchiveInfo->{'PatientName'};
    my $subjectIDsref = Settings::getSubjectIDs(
        $patientName, $patientID, $scannerID, $dbhr, $this->{'db'}
    );

    if (!$subjectIDsref->{'createVisitLabel'}) {
	my $configOB = $this->{'configOB'};
        $subjectIDsref->{'createVisitLabel'} = $configOB->getCreateVisit();
    }

    if (!$subjectIDsref->{'ProjectID'}) {
        my $projectID = NeuroDB::MRI::getProject($subjectIDsref, $dbhr, $this->{'db'});
        $subjectIDsref->{'ProjectID'} = $projectID;
    }

    if (!$subjectIDsref->{'CohortID'}) {
        $subjectIDsref->{'CohortID'} = NeuroDB::MRI::getCohort(
            $subjectIDsref, $subjectIDsref->{'ProjectID'}, $dbhr, $this->{'db'}
        );
    }

    # create the candidate if it does not exist
    $this->CreateMRICandidates(
        $subjectIDsref, $tarchiveInfo, $User, $centerID, $upload_id
    );

    # check if the candidate information is valid
    $subjectIDsref->{'CandMismatchError'} = $this->validateCandidate($subjectIDsref, $upload_id);

    if ($to_log) {
        my $message = sprintf(
            "\n==> Data found for candidate CandID: %s, PSCID %s, Visit %s, Acquisition Date %s\n ",
            $subjectIDsref->{'CandID'}      // 'UNKNOWN',
            $subjectIDsref->{'PSCID'}       // 'UNKNOWN',
            $subjectIDsref->{'visitLabel'}  // 'UNKNOWN',
            $tarchiveInfo->{'DateAcquired'} // 'UNKNOWN'
        );
        $this->{LOG}->print($message);
        $this->spool($message, 'N', $upload_id, $notify_detailed);
    }

    # return the subjectID hash
    return $subjectIDsref;
}


=pod

=head3 createTarchiveArray($tarchive)

Creates the DICOM archive information hash ref for the tarchive that has the same
basename as the file path passed as argument. For HRRT scanners, it will do the
same but from the hrrtarchive table.

INPUTS:
  - $tarchive: tarchive's path (absolute or relative).
  - $hrrt    : whether the archive is from an HRRT scanner or not (in
               which case, the C<hrrt_archive> table will be read
               instead of the C<tarchive> table.

RETURNS: DICOM/HRRT archive information hash ref if exactly one archive was found. Exits
         when either no match or multiple matches are found.

=cut

sub createTarchiveArray {

    my $this = shift;
    my ($tarchive, $hrrt) = @_;

    if ($hrrt) {

        my %tarchiveInfo;
        (my $query = <<QUERY) =~ s/\n/ /gm;
        SELECT
          PatientName,    CenterName,      DateAcquired,
          Blake2bArchive, ArchiveLocation, HrrtArchiveID
        FROM
          hrrt_archive
        WHERE
          ArchiveLocation LIKE ?
QUERY

        if ($this->{debug}) {
            print $query . "\n";
        }

        my $sth = ${$this->{'dbhr'}}->prepare($query);
        $sth->execute("%".basename($tarchive)."%");

        if ($sth->rows > 0) {
            my $tarchiveInfoRef = $sth->fetchrow_hashref();
            %tarchiveInfo = %$tarchiveInfoRef;
        } else {
            my $message = "\nERROR: Only archived data can be uploaded.".
                "This seems not to be a valid archive for this study!".
                "\n\n";
            $this->writeErrorLog($message, $NeuroDB::ExitCodes::SELECT_FAILURE);
            # no $tarchive can be fetched so $upload_id is undef
            # in the notification_spool
            $this->spool($message, 'Y', undef, $notify_notsummary);
            exit $NeuroDB::ExitCodes::SELECT_FAILURE;
        }

        return %tarchiveInfo;

    } else {

        my $tarchiveOB = NeuroDB::objectBroker::TarchiveOB->new(db => $this->{'db'});
        my $tarchiveInfoRef = $tarchiveOB->getByTarchiveLocation($tarchive);

        if (!@$tarchiveInfoRef) {
            my $message = "\nERROR: Only archived data can be uploaded.".
                "This seems not to be a valid archive for this study!".
                "\n\n";
            $this->writeErrorLog($message, $NeuroDB::ExitCodes::SELECT_FAILURE);
            # no $tarchive can be fetched so $upload_id is undef
            # in the notification_spool
            $this->spool($message, 'Y', undef, $notify_notsummary);
            exit $NeuroDB::ExitCodes::SELECT_FAILURE;
        } elsif (@$tarchiveInfoRef > 1) {
            my $message = "\nERROR: Found multiple archives with the same basename ".
                " as $tarchive when only one match was expected!".
                "\n\n";
            $this->writeErrorLog($message, $NeuroDB::ExitCodes::SELECT_FAILURE);
            # Since multiple tarchives were found we cannot determine the upload ID
            # Set it to  undef for this notification
            $this->spool($message, 'Y', undef, $notify_notsummary);
            exit $NeuroDB::ExitCodes::SELECT_FAILURE;
        }

        # Only one archive matches: return it as a hash
        return %{ $tarchiveInfoRef->[0] };

    }
}

=pod

=head3 createMriUploadArray($uploadID)

Creates the MRI upload information hash ref for the uploadID passed as argument.

INPUTS:
  - $uploadID: UploadID to query mri_upload

RETURNS: MRI upload information hash ref if found a row for UploadID in mri_upload.
         Exits when either no match is found.

=cut

sub createMriUploadArray {
    my $this = shift;
    my ($uploadID) = @_;

    my $mriUploadOB = NeuroDB::objectBroker::MriUploadOB->new(db => $this->{'db'});
    my $mriUploadInfoRef = $mriUploadOB->getWithUploadID($uploadID);

    if (!@$mriUploadInfoRef) {
        my $message = "\nERROR: UploadID $uploadID not found in mri_upload\n\n";
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::SELECT_FAILURE);
        # no $tarchive can be fetched so $upload_id is undef
        # in the notification_spool
        $this->spool($message, 'Y', undef, $notify_notsummary);
        exit $NeuroDB::ExitCodes::SELECT_FAILURE;
    }

    # Only one upload: return it as a hash
    return %{ $mriUploadInfoRef->[0] };
}


=pod

=head3 determinePSC($tarchiveInfo, $to_log, $upload_id)

Determines the PSC based on the DICOM archive information hash ref.

INPUTS:
  - $tarchiveInfo: DICOM archive information hash ref
  - $to_log      : boolean, whether this step should be logged
  - $upload_id   : upload ID of the study

RETURNS: array of two elements: center name and center ID

=cut

sub determinePSC {

    my $this = shift;
    my ($tarchiveInfo, $to_log, $upload_id) = @_;
    $to_log = 1 unless defined $to_log;

    # ----------------------------------------------------------------
    ## Get config settings using ConfigOB
    # ----------------------------------------------------------------
    my $configOB              = $this->{'configOB'};
    my $lookupCenterNameUsing = $configOB->getLookupCenterNameUsing();


    my ($center_name, $centerID) =
    NeuroDB::MRI::getPSC(
        $tarchiveInfo->{$lookupCenterNameUsing},
        $this->{dbhr},
        $this->{'db'}
    );
    if ($to_log) {
        if (!$center_name) {

            my $message = "\nERROR: No center found for this candidate \n\n";
            $this->writeErrorLog(
                $message, $NeuroDB::ExitCodes::SELECT_FAILURE
            );
            $this->spool($message, 'Y', $upload_id, $notify_notsummary);
                exit $NeuroDB::ExitCodes::SELECT_FAILURE;
            }
            my $message = "\n==> Verifying acquisition center\n-> " .
                          "Center Name : $center_name\n-> CenterID ".
                          " : $centerID\n";
            $this->{LOG}->print($message);
            $this->spool($message, 'N', $upload_id, $notify_detailed);
    }

    return ($center_name, $centerID);
}


=pod

=head3 determineProjectID($tarchiveInfo)

Determines the Project.

INPUTS:
  - $tarchiveInfo: archive information hash ref

RETURNS: project ID

=cut

sub determineProjectID {

    my $this = shift;
    my ($tarchiveInfo) = @_;
    my $subjectIDsref = Settings::getSubjectIDs(
        $tarchiveInfo->{'PatientName'},
        undef,
        undef,
        $this->{dbhr},
        $this->{db}
    );

    if (defined $subjectIDsref->{'ProjectID'}) {
        return $subjectIDsref->{'ProjectID'}
    }

    return NeuroDB::MRI::getProject($subjectIDsref, $this->{dbhr}, $this->{db});
}


=pod

=head3 determineScannerID($tarchiveInfo, $to_log, $centerID, $projectID, $upload_id)

Determines which scanner ID was used for DICOM acquisitions. Note, if
a scanner ID is not already associated to the scanner information found
in the DICOM headers, then a new scanner will automatically be created.

INPUTS:
  - $tarchiveInfo: archive information hash ref
  - $to_log      : whether this step should be logged
  - $centerID    : center ID
  - $projectID   : project ID
  - $upload_id   : upload ID of the study

RETURNS: scanner ID

=cut

sub determineScannerID {

    my $this = shift;
    my ($tarchiveInfo, $to_log, $centerID, $projectID, $upload_id) = @_;
    my $message = '';
    $to_log = 1 unless defined $to_log;
    if ($to_log) {
        $message = "\n\n==> Trying to determine scanner ID\n";
        $this->{LOG}->print($message);
        $this->spool($message, 'N', $upload_id, $notify_detailed);
    }

    my $scannerID =
        NeuroDB::MRI::findScannerID(
            $tarchiveInfo->{'ScannerManufacturer'},
            $tarchiveInfo->{'ScannerModel'},
            $tarchiveInfo->{'ScannerSerialNumber'},
            $tarchiveInfo->{'ScannerSoftwareVersion'},
            $centerID,
            $projectID,
            $this->{dbhr},
            $this->{'db'}
        );
    if ($scannerID == 0) {
        if ($to_log) {
            $message = "\nERROR: The ScannerID for this particular scanner ".
                          "does not exist and could not be created.\n\n";
            $this->writeErrorLog(
                $message, $NeuroDB::ExitCodes::SELECT_FAILURE
            );
            $this->spool($message, 'Y', $upload_id, $notify_notsummary);
            exit $NeuroDB::ExitCodes::SELECT_FAILURE;
        }
    }
    if ($to_log) {
        $message = "==> scanner ID : $scannerID\n\n";
        $this->{LOG}->print($message);
        $this->spool($message,'N', $upload_id, $notify_detailed);
    }
    return $scannerID;
}


=pod

=head3 get_acqusitions($study_dir, \@acquisitions)

UNUSED

=cut

sub get_acquisitions {
    my $this = shift;
    my ($study_dir, $acquisitions) = @_;
    @$acquisitions =
    split("\n", `find $study_dir -type d -name \\*.ACQ`);
    my $message = "Acquisitions: ".join("\n", @$acquisitions)."\n";
    if ($this->{verbose}){
        $this->{LOG}->print($message);
    }
}


=pod

=head3 computeMd5Hash($file, $upload_id)

Computes the MD5 hash of a file and makes sure it is unique.

INPUTS:
  - $file     : file to use to compute the MD5 hash
  - $upload_id: upload ID of the study

RETURNS: 1 if the file is unique, 0 otherwise

=cut

sub computeMd5Hash {
    my $this = shift;
    my ($file, $upload_id) = @_;
    my $message = '';
    $message = "\n==> computing md5 hash for MINC body.\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    my $md5hash = &NeuroDB::MRI::compute_hash(\$file);
    $message = "\n--> md5: $md5hash\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    $file->setParameter('md5hash', $md5hash);
    my $unique = &NeuroDB::MRI::is_unique_hash(\$file);
    return $unique;
}


=pod

=head3 getAcquisitionProtocol($file, $subjectIDsref, $tarchiveInfo, $centerID, $minc, $acquisitionProtocol, $bypass_extra_file_checks, $upload_id, $data_dir)

Determines the acquisition protocol and acquisition protocol ID for the MINC
file. If C<$acquisitionProtocol> is not set, it will look for the acquisition
protocol in the C<mri_protocol> table based on the MINC header information
using C<&NeuroDB::MRI::identify_scan_db>. If C<$bypass_extra_file_checks> is
true, then it will bypass the additional protocol checks from the
C<mri_protocol_checks> table using C<&extra_file_checks>.

INPUTS:
  - $file                    : file's information hash ref
  - $subjectIDsref           : subject's information hash ref
  - $tarchiveInfo            : DICOM archive's information hash ref
  - $centerID                : ID of the center where the scan was acquired.
  - $minc                    : absolute path to the MINC file
  - $acquisitionProtocol     : acquisition protocol if already knows it
  - $bypass_extra_file_checks: boolean, if set bypass the extra checks
  - $upload_id               : upload ID of the study
  - $data_dir                : path to the LORIS MRI data directory


RETURNS:
  - $acquisitionProtocol     : acquisition protocol
  - $acquisitionProtocolID   : acquisition protocol ID
  - $extra_validation_status : extra validation status ("pass", "exclude", "warning") or
                               C<undef> if C<$bypass_extra_file_checks> is set.

=cut

sub getAcquisitionProtocol {

    my $this = shift;
    my ($file,$subjectIDsref,$tarchiveInfoRef,$centerID,$minc,
        $acquisitionProtocol,$bypass_extra_file_checks, $upload_id, $data_dir) = @_;
    my $message = '';

    ############################################################
    ## get acquisition protocol (identify the volume) ##########
    ############################################################

    if(!defined($acquisitionProtocol)) {
      $message = "\n==> verifying acquisition protocol\n";
      $this->{LOG}->print($message);
      $this->spool($message, 'N', $upload_id, $notify_detailed);

      $acquisitionProtocol =  &NeuroDB::MRI::identify_scan_db(
                                   $centerID,
                                   $subjectIDsref,
                                   $tarchiveInfoRef,
                                   $file,
                                   $this->{dbhr},
                                   $this->{'db'},
                                   $minc,
                                   $upload_id,
                                   $data_dir
                                 );
    }

    $message = "\nAcquisition protocol is $acquisitionProtocol\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);

    my $extra_validation_status;
    my $acquisitionProtocolID;
    if ($acquisitionProtocol !~ /unknown/) {
        $acquisitionProtocolID = NeuroDB::MRI::scan_type_text_to_id(
            $acquisitionProtocol, $this->{'db'}
        );

        # if no acquisition protocol ID returned, look for the 'unknown' protocol ID
        unless ($acquisitionProtocolID) {
            $acquisitionProtocolID = NeuroDB::MRI::scan_type_text_to_id(
                'unknown', $this->{'db'}
            );
            # if found an ID for 'unknown' scan type, then change protocol
            # to be 'unknown', otherwise throw an error
            if ($acquisitionProtocolID) {
                $acquisitionProtocol = 'unknown';
            } else {
                NeuroDB::UnexpectedValueException->throw(
                    errorMessage => sprintf(
                        "Unknown acquisition protocol %s and scan type 'unknown' does not exist in the database",
                        $acquisitionProtocol
                    )
                );
            }
        }

        if ($bypass_extra_file_checks == 0) {
            $extra_validation_status = $this->extra_file_checks(
                $acquisitionProtocolID,
                $file,
                $subjectIDsref,
                $tarchiveInfoRef->{'PatientName'},
                $data_dir
            );
            $message = "\nextra_file_checks from table mri_protocol_check " .
                     "logged in table mri_violations_log: $extra_validation_status\n";
            $this->{LOG}->print($message);

            # 'warn' and 'exclude' are errors, while 'pass' is not
            # log in the notification_spool_table the $Verbose flag accordingly
            if ($extra_validation_status ne 'pass'){
                $this->spool($message, 'Y', $upload_id, $notify_notsummary);
            }
            else {
                $this->spool($message, 'N', $upload_id, $notify_detailed);
            }
        }
    } else {
        $acquisitionProtocolID = NeuroDB::MRI::scan_type_text_to_id(
            $acquisitionProtocol, $this->{'db'}
        );
    }

    return ($acquisitionProtocol, $acquisitionProtocolID, $extra_validation_status);
}


=pod

=head3 extra_file_checks($scan_type, $file, $subjectIdsref, $pname, $data_dir)

Returns the list of MRI protocol checks that failed. Can't directly insert
this information here since the file isn't registered in the database yet.

INPUTS:
  - $scan_type    : scan type of the file
  - $file         : file information hash ref
  - $subjectIdsref: context information for the scan
  - $pname        : patient name found in the scan header
  - $data_dir     : path to the LORIS MRI data directory

RETURNS:
  - pass, warn or exclude flag depending on the worst failed check
  - array of failed checks if any were failed

=cut

sub extra_file_checks() {

    my $this          = shift;
    my $scan_type     = shift;
    my $file          = shift;
    my $subjectIDsref = shift;
    my $pname         = shift;
    my $data_dir      = shift;

    my $candID        = $subjectIDsref->{'CandID'};
    my $projectID     = $subjectIDsref->{'ProjectID'};
    my $cohortID      = $subjectIDsref->{'CohortID'};
    my $visitLabel    = $subjectIDsref->{'visitLabel'};

    ## Step 1 - select all distinct exclude and warning headers for the scan type
    my $query = "SELECT DISTINCT(mpc.Header) FROM mri_protocol_checks mpc "
              . "JOIN mri_protocol_checks_group_target mpcgt USING(MriProtocolChecksGroupID) "
              . "WHERE MriScanTypeID=? AND Severity=?";
    $query .= defined $projectID
        ? ' AND (mpcgt.ProjectID IS NULL OR mpcgt.ProjectID = ?)'
        : ' AND mpcgt.ProjectID IS NULL';
    $query .= defined $cohortID
        ? ' AND (mpcgt.CohortID IS NULL OR mpcgt.CohortID = ?)'
        : ' AND mpcgt.CohortID IS NULL';
    $query .= defined $visitLabel
        ? ' AND (mpcgt.Visit_label IS NULL OR mpcgt.Visit_label = ?)'
        : ' AND mpcgt.Visit_label IS NULL';
    my $sth   = ${$this->{'dbhr'}}->prepare($query);
    if ($this->{debug}) {
        print $query . "\n";
    }

    # Step 2 - loop through all severities and grep headers, valid fields and
    # check if the scan is valid. If the scan is not valid, then, return the
    # severity of the failure.
    foreach my $severity (qw/exclude warning/) {
        my @bindValues = ($scan_type, $severity);
        push(@bindValues, $projectID)    if defined $projectID;
        push(@bindValues, $cohortID) if defined $cohortID;
        push(@bindValues, $visitLabel)   if defined $visitLabel;
        $sth->execute(@bindValues);

        my @headers = map { $_->{'Header'} } @{ $sth->fetchall_arrayref({}) };
        my %validFields = $this->loop_through_protocol_violations_checks(
            $scan_type, $severity, \@headers, $file, $projectID, $cohortID, $visitLabel
        );
        if (%validFields) {
            $this->insert_into_mri_violations_log(
                \%validFields, $severity, $pname, $candID, $visitLabel, $file, $data_dir, $scan_type
            );
            return $severity;
        }
    }

    ## Step 3 - if we end up here, then the file passes the extra validation
    # checks and return 'pass'
    return ('pass');
}


=pod

=head3 update_mri_violations_log_MincFile_path($file_ref)

This function updates the C<MincFile> field of the C<mri_violations_log> table
with the file path present in the files table.

Note: this needs to be updated as by default the path is set to be in the C<trashbin>
directory when inserting into the C<mri_violations_log> table. However, if the
worst violation is set to 'warning', the MINC file will get inserted into the
C<files> table and moved to the C<assembly> directory, therefore it needs to be
updated in the C<mri_violations_log> table.

INPUTS: file handle reference to the NeuroDB::File object

=cut

sub update_mri_violations_log_MincFile_path {
    my ($this, $file_ref) = @_;

    # grep file parameters determining a unique file in the DB
    my $seriesUID   = $file_ref->getParameter('series_instance_uid');
    my $echoTime    = $file_ref->getParameter('echo_time');
    my $phEncDir    = $file_ref->getParameter('phase_encoding_direction');
    my $echoNumbers = $file_ref->getParameter('echo_numbers');

    # determine the new file path to use for update
    my $file_path   = $file_ref->getFileDatum('File');

    (my $query = <<QUERY) =~ s/\n/ /gm;
    UPDATE mri_violations_log
    SET MincFile = ?
    WHERE SeriesUID = ? AND EchoTime = ? AND PhaseEncodingDirection = ? AND EchoNumber = ?
QUERY
    my $sth   = ${$this->{'dbhr'}}->prepare($query);

    $sth->execute($file_path, $seriesUID, $echoTime, $phEncDir, $echoNumbers);
}

=pod

=head3 loop_through_protocol_violations_checks($scan_type, $severity, $headers, $file, $projectID, $cohortID, $visitLabel)

Loops through all protocol violations checks for a given severity and creates
a hash with all the checks that need to be applied on that specific scan type
and severity.

INPUTS:
  - $scan_type   : scan type of the file
  - $severity    : severity of the checks we want to loop through (exclude or warning)
  - $headers     : list of different headers found in the C<mri_protocol_checks>
                   table for a given scan type
  - $file        : file information hash ref
  - $projectID   : candidate's project ID
  - $cohortID    : session's cohort ID
  - $visitLabel  : session name

RETURNS: a hash with all information about the checks for a given scan type
and severity

=cut

sub loop_through_protocol_violations_checks {
    my ($this, $scan_type, $severity, $headers, $file, $projectID, $cohortID, $visitLabel) = @_;

    my %valid_fields; # will store all information about what fails

    # query to fetch list of valid protocols in mri_protocol_checks table
    my $query = "SELECT * FROM mri_protocol_checks mpc "
              . "JOIN mri_protocol_checks_group_target mpcgt USING(MriProtocolChecksGroupID) "
              . "WHERE mpc.MriScanTypeID=? AND mpc.Severity=? AND mpc.Header=? ";
    $query .= defined $projectID
        ? ' AND (mpcgt.ProjectID IS NULL OR mpcgt.ProjectID = ?)'
        : ' AND mpcgt.ProjectID IS NULL';
    $query .= defined $cohortID
        ? ' AND (mpcgt.CohortID IS NULL OR mpcgt.CohortID = ?)'
        : ' AND mpcgt.CohortID IS NULL';
    $query .= defined $visitLabel
        ? ' AND (mpcgt.Visit_label IS NULL OR mpcgt.Visit_label = ?)'
        : ' AND mpcgt.Visit_label IS NULL';
    my $sth   = ${$this->{'dbhr'}}->prepare($query);

    # loop through all severity headers for the scan type and check if in the
    # value of the header in the file fits one of the valid range present in
    # mri_protocol_checks
    foreach my $header (@$headers) {
        # get the value from the file
        my $value = $file->getParameter($header);

        # execute query for $scan_type, $severity, $header and (possibly)
        # $projectID, $cohortID and $visitLabel
        my @bindValues = ($scan_type, $severity, $header);
        push(@bindValues, $projectID)    if defined $projectID;
        push(@bindValues, $cohortID) if defined $cohortID;
        push(@bindValues, $visitLabel)   if defined $visitLabel;
        $sth->execute(@bindValues);

        # grep all valid ranges and regex to compare with value in the file
        my (@valid_ranges, @valid_regexs, $mriProtocolChecksGroupID);
        while (my $row= $sth->fetchrow_hashref) {
            if (defined $row->{'ValidMin'} || defined $row->{'ValidMax'}) {
                my $valid_range = "$row->{'ValidMin'}-$row->{'ValidMax'}";
                push(@valid_ranges, $valid_range);
            }
            push(@valid_regexs, $row->{'ValidRegex'}) if $row->{'ValidRegex'};

            # the group on each row should be the same if the mri_protocol_checks_group_target
            # table was setup properly
            $mriProtocolChecksGroupID = $row->{'MriProtocolChecksGroupID'};
        }

        # go to the next header if did not find any checks for that scan
        # type, severity and header
        next if (!@valid_ranges && !@valid_regexs);

        # loop through all checks
        next if grep(NeuroDB::MRI::in_range($value, $_), @valid_ranges);
        next if grep($value =~ /$_/, @valid_regexs);

        $valid_fields{$header} = {
            ScanType                 => $scan_type,
            HeaderValue              => $value,
            ValidRanges              => [ map { $_ } @valid_ranges ],
            ValidRegexs              => [ map { $_ } @valid_regexs ],
            MriProtocolChecksGroupID => $mriProtocolChecksGroupID
        };
    }

    return %valid_fields;
}

=pod

=head3 insert_into_mri_violations_log($valid_fields, $severity, $pname, $candID, $visit_label, $file, $data_dir)

For a given protocol failure, it will insert into the C<mri_violations_log>
table all the information about the scan and the protocol violation.

INPUTS:
  - $valid_fields: string with valid values for the header and scan type
  - $severity    : severity of the violation ("exclude" or "warning")
  - $pname       : Patient name associated with the scan
  - $candID      : C<CandID> associated with the scan
  - $visit_label : visit label associated with the scan
  - $file        : information about the scan
  - $data_dir    : path to the LORIS MRI data directory
  - $scan_type   : scan type associated to the file

=cut

sub insert_into_mri_violations_log {
    my ($this, $valid_fields, $severity, $pname, $candID, $visit_label, $file, $data_dir, $scan_type) = @_;

    my $tarchiveID = $file->getFileDatum('TarchiveSource');

    # determine the future relative path when the file will be moved to
    # data_dir/trashbin at the end of the script's execution
    my $file_path        = $file->getFileDatum('File');
    my $move_file        = $severity eq 'exclude' ? 1 : undef;
    my $file_rel_path    = NeuroDB::MRI::get_trashbin_file_rel_path($file_path, $data_dir, $move_file);


    #------------------------------------------#
    # Find the CandidateID of candidate with   #
    # CandID=$candID                           #
    #------------------------------------------#
    my $query = "SELECT ID FROM candidate WHERE CandID=?";
    my $rowsref = ${$this->{'dbhr'}}->selectall_arrayref($query, { Slice=> {} }, $candID);

    if (@$rowsref != 1) {
        NeuroDB::UnexpectedValueException->throw(
            errorMessage => sprintf(
                "Unexpected number of candidates with CandID set to %s (should be 1 but was %d)",
                 $candID,
                 scalar(@$rowsref)
            )
        );
    }

    my $candidateID = $rowsref->[0]->{'ID'};

    my %newViolationsLog = (
        'TarchiveID'             => $tarchiveID,
        'SeriesUID'              => $file->getFileDatum('SeriesUID'),
        'MincFile'               => $file_rel_path,
        'PatientName'            => $pname,
        'CandidateID'            => $candidateID,
        'Visit_label'            => $visit_label,
        'MriScanTypeID'          => $scan_type,
        'Severity'               => $severity,
        'EchoTime'               => $file->getParameter('echo_time'),
        'PhaseEncodingDirection' => $file->getParameter('phase_encoding_direction'),
        'EchoNumber'             => $file->getParameter('echo_numbers')
    );

    my $mriViolationsLogOB = NeuroDB::objectBroker::MriViolationsLogOB->new(db => $this->{db});
    my $mriViolationsLogRef = $mriViolationsLogOB->getWithTarchiveID($tarchiveID);

    # foreach header, concatenate arrays of ranges into a string
    foreach my $header (keys(%$valid_fields)) {
        $file->setFileData('Caveat', 1) if ($severity eq 'warning');

        my $valid_range_str  = "NULL";
        my $valid_regex_str  = "NULL";
        my @valid_range_list = @{ $valid_fields->{$header}{ValidRanges} };
        my @valid_regex_list = @{ $valid_fields->{$header}{ValidRegexs} };
        if (@valid_range_list) {
            $valid_range_str = join(',', @valid_range_list);
        }
        if (@valid_regex_list) {
            $valid_regex_str = join(',', @valid_regex_list);
        }

        $newViolationsLog{'Header'}     = $header;
        $newViolationsLog{'Value'}      = $valid_fields->{$header}{HeaderValue};
        $newViolationsLog{'ValidRange'} = $valid_range_str;
        $newViolationsLog{'ValidRegex'} = $valid_regex_str;
        $newViolationsLog{'MriProtocolChecksGroupID'} = $valid_fields->{$header}{MriProtocolChecksGroupID};

        my $already_inserted = undef;
        foreach my $dbViolLog (@$mriViolationsLogRef) {
            if ($dbViolLog->{'SeriesUID'} eq $newViolationsLog{'SeriesUID'}
                && $dbViolLog->{'EchoTime'} eq $newViolationsLog{'EchoTime'}
                && $dbViolLog->{'EchoNumber'} eq $newViolationsLog{'EchoNumber'}
                && $dbViolLog->{'PhaseEncodingDirection'} eq $newViolationsLog{'PhaseEncodingDirection'}
                && $dbViolLog->{'MriScanTypeID'} eq $newViolationsLog{'MriScanTypeID'}
                && $dbViolLog->{'Severity'} eq $newViolationsLog{'Severity'}
                && $dbViolLog->{'Header'} eq $newViolationsLog{'Header'}
                && $dbViolLog->{'Value'} eq $newViolationsLog{'Value'}
                && $dbViolLog->{'ValidRange'} eq $newViolationsLog{'ValidRange'}
                && $dbViolLog->{'ValidRegex'} eq $newViolationsLog{'ValidRegex'}
            ) {
                $already_inserted = 1;
                last;
            }
        }
        $mriViolationsLogOB->insert(\%newViolationsLog) unless defined $already_inserted;
    }
}




=pod

=head3 loadAndCreateObjectFile($minc, $upload_id)

Loads and creates the object file.

INPUTS:
  - $minc     : location of the minc file
  - $upload_id: upload ID of the study

RETURNS: file information hash ref

=cut

sub loadAndCreateObjectFile {

    my $this = shift;
    my ($minc, $upload_id) = @_;
    my $message = '';

    ############################################################
    ################ create File object ########################
    ############################################################
    my $file = NeuroDB::File->new($this->{dbhr});

    ############################################################
    ########## load File object ################################
    ############################################################
    $message =  "\n==> Loading file from disk $minc\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    $file->loadFileFromDisk($minc);

    ############################################################
    ############# map dicom fields #############################
    ############################################################
    $message = "\n--> mapping DICOM parameter for $minc\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    NeuroDB::MRI::mapDicomParameters(\$file);
    return $file;
}


=pod

=head3 move_minc($minc, $subjectIDsref, $minc_type, $prefix, $data_dir, $hrrt, $upload_id)

Renames and moves the MINC file.

INPUTS:
  - $minc           : path to the MINC file
  - $subjectIDsref  : subject's ID hash ref
  - $minc_type      : acquisition protocol
  - $prefix         : study prefix
  - $data_dir       : data directory (e.g. C</data/$PROJECT/data>)
  - $hrrt           : boolean, whether the file comes from a PET HRRT scanner
  - $upload_id      : upload ID of the study

RETURNS: new name of the MINC file with path relative to C<$data_dir>

=cut

sub move_minc {

    my $this = shift;
    my ($minc, $subjectIDsref, $minc_type, $prefix, $data_dir, $hrrt, $upload_id) = @_;
    my ($new_name, $version,$cmd,$new_dir,$extension,@exts,$dir);
    my $concat = "";
    my $message = '';

    ############################################################
    ### figure out where to put the files ######################
    ############################################################
    $dir = $this->which_directory($subjectIDsref, $data_dir, $hrrt);
    `mkdir -p -m 770 $dir/native`;

    ############################################################
    ####### figure out what to call files ######################
    ############################################################
    @exts = split(/\./, basename($$minc));
    shift @exts;
    $extension = $hrrt ? pop @exts : join('.', @exts);
    $concat = '_concat' if $$minc =~ /_concat/;
    $new_dir = "$dir/native";
    $version = 1;
    $new_name = $prefix."_".$subjectIDsref->{'CandID'}."_".
                $subjectIDsref->{'visitLabel'}.
                "_". $minc_type."_".sprintf("%03d",$version).
                $concat.".$extension";
    $new_name =~ s/ //;
    $new_name =~ s/__+/_/g;
    while(-e "$new_dir/$new_name") {
        $version = $version + 1;
        $new_name =  $prefix."_".$subjectIDsref->{'CandID'}."_".
                     $subjectIDsref->{'visitLabel'}."_".$minc_type."_".
                     sprintf("%03d",$version).$concat.".$extension";
        $new_name =~ s/ //;
        $new_name =~ s/__+/_/g;
    }
    $new_name = "$new_dir/$new_name";
    $cmd = "mv $$minc $new_name";
    `$cmd`;
    $message = "\nFile $$minc \nmoved to:\n$new_name\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    $$minc = $new_name;
    return $new_name;
}


=pod

=head3 registerScanIntoDB($minc_file, $tarchiveInfo, $subjectIDsref, $acquisitionProtocol, $minc, $extra_validation_status, $reckless, $sessionID, $upload_id, $hrrt)

Registers the scan into the database.

INPUTS:
  - $minc_file               : MINC file information hash ref
  - $tarchiveInfo            : tarchive information hash ref
  - $subjectIDsref           : subject's ID information hash ref
  - $acquisitionProtocol     : acquisition protocol
  - $minc                    : MINC file to register into the database
  - $$extra_validation_status: extra validation status (if 'exclude', then
                               will not register the scan in the files table)
  - $reckless                : boolean, if reckless or not
  - $sessionID               : session ID of the MINC file
  - $upload_id               : upload ID of the study
  - $hrrt                    : boolean, whether the file comes from a PET HRRT scanner

RETURNS: acquisition protocol ID of the MINC file

=cut

sub registerScanIntoDB {

    my $this = shift;
    my (
        $minc_file, $tarchiveInfo,$subjectIDsref,$acquisitionProtocol,
        $minc, $extra_validation_status,$reckless, $sessionID, $upload_id,
        $acquisitionProtocolID, $hrrt
    ) = @_;


    # ----------------------------------------------------------------
    ## Get config settings using ConfigOB
    # ----------------------------------------------------------------
    my $configOB = $this->{'configOB'};
    my $data_dir = $configOB->getDataDirPath();
    my $prefix   = $configOB->getPrefix();


    my ($Date_taken, $minc_protocol_identified, $file_path, $tarchive_path, $fileID);
    my $message = '';
    ############################################################
    # Register scans into the database.  Which protocols to ####
    # keep optionally controlled by the config file. ###########
    ############################################################
    if ((!defined(&Settings::isFileToBeRegisteredGivenProtocol)
        || $reckless
        || (defined(&Settings::isFileToBeRegisteredGivenProtocol)
            && Settings::isFileToBeRegisteredGivenProtocol($acquisitionProtocol)
           )
        )
        && (!defined($extra_validation_status) || $extra_validation_status !~ /exclude/)) {

        $${minc_file}->setFileData(
            'MriScanTypeID',
            $acquisitionProtocolID
        );

        $message = "\nAcq protocol: $acquisitionProtocol "
            . "- ID: $acquisitionProtocolID\n";
        $this->spool($message, 'N', $upload_id, $notify_detailed);

        ########################################################
        # set Date_taken = last modification timestamp #########
        # (can't seem to get creation timestamp) ################
        ########################################################
        $Date_taken = (stat($minc))[9];

        ########################################################
        ##### rename and move files ############################
        ########################################################
        $minc_protocol_identified = $this->move_minc(
            \$minc,    $subjectIDsref, $acquisitionProtocol,
            $prefix,   $data_dir,      $hrrt,
            $upload_id
        );

        ########################################################
        #################### set the new file_path #############
        ########################################################
        $file_path =  $minc;
        $file_path =~ s/$data_dir\///i;
        $${minc_file}->setFileData(
            'File',
            $file_path
        );

        #### set the acquisition_date
        my $study_start_date = (
            defined($${minc_file}->getParameter('study:start_year'))
            && defined($${minc_file}->getParameter('study:start_month'))
            && defined($${minc_file}->getParameter('study:start_day'))
            ? DateTime->new(
                day        => $${minc_file}->getParameter('study:start_day'),
                month      => $${minc_file}->getParameter('study:start_month'),
                year       => $${minc_file}->getParameter('study:start_year'),
            )->strftime('%Y-%m-%d')
            : undef
        );

        my $acquisition_date =
            $${minc_file}->getParameter('acquisition_date')
            || $study_start_date
            || undef;

        print "Acquisition date: " . $acquisition_date . "\n";

        $${minc_file}->setFileData(
            'AcquisitionDate',
            $acquisition_date
        );



        ########################################################
        ### record which tarchive was used to make this file ###
        ########################################################
        $tarchive_path =  $tarchiveInfo->{ArchiveLocation};
        my $md5sumField     = $hrrt ? 'hrrt_archiveLocation' : 'tarchiveLocation';
        my $archiveLocField = $hrrt ? 'hrrt_archiveMD5'      : 'tarchiveMD5';
        if ($tarchive_path) {
            $tarchive_path =~ s/$data_dir\///i;
            $${minc_file}->setParameter($archiveLocField, $tarchive_path);
            $${minc_file}->setParameter($md5sumField,     $tarchiveInfo->{'md5sumArchive'});
        }

        ########################################################
        # register into the db fixme if I ever want a dry run ##
        ########################################################
        $message = "\nRegistering file into database\n";
        $this->spool($message, 'N', $upload_id, $notify_detailed);
        $fileID = &NeuroDB::MRI::register_db($minc_file);
        $message = "\nFileID: $fileID\n";
        $this->spool($message, 'N', $upload_id, $notify_detailed);

        return 1;
    }

    return undef;
}


=pod

=head3 dicom_to_minc($study_dir, $converter, $get_dicom_info, $mail_user, $upload_id, @exclude)

Converts a DICOM study into MINC files.

INPUTS:
  - $study_dir      : DICOM study directory to convert
  - $converter      : converter to be used
  - $get_dicom_info : get DICOM information setting from the C<Config> table
  - $mail_user      : mail of the user
  - $upload_id      : upload ID of the study
  - @exclude        : which files to exclude from the C<dcm2mnc> command

=cut

sub dicom_to_minc {
    my $this = shift;
    my ($study_dir, $converter, $get_dicom_info, $mail_user, $upload_id, @exclude) = @_;
    my ($d2m_cmd, $d2m_log, $exit_code, $excluded_regex);
    my $message = '';

    if (!-e $get_dicom_info) {
        print "Warning! Value '$get_dicom_info' (config setting get_dicom_info) is not an existing script!\n";
        return;
    }

    if (!-x $get_dicom_info) {
        print "Warning! Script '$get_dicom_info' (config setting get_dicom_info) is not an executable script!\n";
        return;
    }

    #--------------------------------------------------------------------------------#
    # Create the excluded series description regex necessary to exclude the          #
    # series description specified in the Config Setting excluded_series_description #
    # If there are no series to exclude, $excluded_regex remains undef               #
    #--------------------------------------------------------------------------------#
    $excluded_regex = join('|', map { quotemeta($_) } @exclude) if (@exclude);

    #-----------------------------------------------------------------------------------#
    # Run get_dicom_info on all the DICOM files and build the set of all the distinct   #
    # quadruplets (studyUID, seriesUID, echoTime, seriesDescription). These quadruplets #
    # identify the DICOM files that belong to a specific group (modality in fact)       #
    #-----------------------------------------------------------------------------------#
    my $cmd = "find $study_dir -type f "
         . "| $get_dicom_info -studyuid -attvalue 0020 000e -echo -series_descr -stdin";
    $cmd .= ' | grep -iv -P "\t(' . $excluded_regex . ')\s*$"' if ($excluded_regex);
    $cmd .= " | sort | uniq";

    my @cmdOutputLines = `$cmd`;

    #------------------------------------------------------------------------------------#
    # For each quadruplet (modality) run dcm2mnc to convert the DICOM files that belong    #
    # in that group. We cannot convert the entire set of DICOM files due to a bug in     #
    # dcm2mnc (see https://github.com/aces/Loris/issues/564). We have to split the      #
    # DICOM files into groups and convert the files that belong to each group separately.#
    #------------------------------------------------------------------------------------#
    foreach my $line (@cmdOutputLines) {
        chomp($line);
        my($studyUID, $seriesUID, $echo, $seriesDesc) = split(/\t/, $line);

        # We need to use quotemeta here to make sure each character of a given variable is interpreted
        # as is and not as a regex special character
        # Note: '$\'\t\'' is a TAB for Unix grep
        my $pattern = join('$\'\t\'', quotemeta($studyUID), quotemeta($seriesUID), quotemeta($echo), quotemeta($seriesDesc));

        # For each file in $study_dir...
        my $d2m_cmd = "find $study_dir -type f ";

        # ...invoke get_dicom_info to get its study UID, series instance UID, echo time, series description and file name
        $d2m_cmd   .= "| $get_dicom_info -studyuid -attvalue 0020 000e -echo -series_descr -file -stdin";

        # ...keep only the files that belong to the current group
        $d2m_cmd   .= "| grep ^$pattern";

        # ...keep only the file name
        $d2m_cmd   .= "| cut -f5";

        if ($converter !~ /dcm2mnc/) {
            $d2m_cmd .= "$converter $this->{TmpDir}  -notape -compress -stdin";
        } else {
            $d2m_cmd .= " | $converter -dname '' -stdin -clobber -usecoordinates $this->{TmpDir} ";
        }

        # forcing bash to make sure ANSI-C quoting ($'\t') is supported.
        # It's not supported in some shells like Ubuntu dash.
        my $d2m_log = `/bin/bash -c "$d2m_cmd"`;

        if ($? > 0) {
            $exit_code = $? >> 8;
            #---------------------------------------------------------#
            # dicom_to_minc failed: bomb out                          #
            #---------------------------------------------------------#
            $message = "\nDicom to Minc conversion failed\n";
            $this->spool($message, 'Y', $upload_id, 'N');
            open MAIL, "| mail $mail_user";
            print MAIL "Subject: [URGENT Automated] uploadNeuroDB: ".
                       "dicom->minc failed\n";
            print MAIL "Exit code $exit_code received from:\n$d2m_cmd\n";
            close MAIL;
            croak("dicom_to_minc failure, exit code $exit_code");
        }

        $message = "\n" . $d2m_cmd . "\n";
        $this->{LOG}->print("### Dicom to MINC:\n$d2m_log");
        $this->spool($message, 'N', $upload_id, 'Y');
    }
}


=pod

=head3 get_mincs($minc_files, $upload_id)

Greps the created MINC files and returns a sorted list of those MINC files.

INPUTS:
  - $minc_files: empty array to store the list of MINC files
  - $upload_id : upload ID of the study

=cut

sub get_mincs {

    my $this = shift;
    my ($minc_files, $upload_id) = @_;
    my $message = '';
    @$minc_files = ();

    opendir TMPDIR, $this->{TmpDir} ;
    my @files = readdir TMPDIR;
    closedir TMPDIR;

    my @files_list;
    foreach my $file (@files) {

        next unless $file =~ /\.mnc(\.gz)?$/;

        my $cmd = sprintf(
            'Mincinfo_wrapper.pl -quiet -tab -file -attvalue %s %s',
            'acquisition:acquisition_id',
            quotemeta("$this->{TmpDir}/$file")
        );
        push @files_list, `$cmd`;

    }

    open SORTER, "|sort -nk2 | cut -f1 > $this->{TmpDir}/sortlist";
    print SORTER join("", @files_list);
    close SORTER;

    open SORTLIST, "<$this->{TmpDir}/sortlist";
    while(my $line = <SORTLIST>) {
        chomp($line);
        push @$minc_files, $line;
    }
    close SORTLIST;

    `rm -f $this->{TmpDir}/sortlist`;

    $message = "\n### These MINC files have been created: \n".
        join("\n", @$minc_files)."\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
}


=pod

=head3 concat_mri($minc_files)

Concats and removes pre-concat MINC files.

INPUT: list of MINC files to concat

=cut

sub concat_mri {

    my $this = shift;
    my ($minc_files) = @_;
    my ($cmd,$log,$concat_count);
    ############################################################
    # make a list of the mincs to concat #######################
    # (avoid arg list too long errors) #########################
    ############################################################
    open CONCATFILES, ">$this->{TmpDir} /concatfilelist.txt";
    foreach my $file (@$minc_files) {
        print CONCATFILES "$file\n";
    }
    close CONCATFILES;
    mkdir("$this->{TmpDir} /concat", 0770);
    $cmd = "cat $this->{TmpDir} /concatfilelist.txt | concat_mri.pl ".
           "-maxslicesep 3.1 -compress -postfix _concat -targetdir ".
           "$this->{TmpDir} /concat -stdin";
    if ($this->{debug}) {
        print $cmd . "\n";
    }

    $log = `$cmd`;
    `rm -f $this->{TmpDir} /concatfilelist.txt`;
    ############################################################
    # fixme print LOG "Concat:\n $cmd\n$log\n" #################
    # if $this->{verbose}; #####################################
    ############################################################
    $concat_count = `\\ls -1 $this->{TmpDir} /concat | wc -l`+0;
    if ($concat_count > 0) {
        `mv $this->{TmpDir} /concat/*.mnc.gz $this->{TmpDir} `;
    }
    `rmdir $this->{TmpDir} /concat`;
    $this->{LOG}->print(
        "### Count for concatenated MINCs: ".
        "$concat_count new files created\n"
    );
}


=pod

=head3 registerProgs(@toregister)

Register programs.

INPUT: program to register

=cut

sub registerProgs() {
    my $this = shift;
    my @toregister = @_;
    foreach my $prog (@toregister) {
        my $present = `which $prog`;
        if (!$present) {
            die("$prog not found")
        };
    }
}


=pod

=head3 moveAndUpdateTarchive($tarchive_location, $tarchiveInfo, $upload_id)

Moves and updates the C<tarchive> table with the new location of the
DICOM archive.

INPUTS:
  - $tarchive_location: DICOM archive location
  - $tarchiveInfo     : DICOM archive information hash ref
  - $upload_id        : upload ID of the study

RETURNS: the new DICOM archive location

=cut

sub moveAndUpdateTarchive {

    my $this = shift;
    my ($tarchive_location, $tarchiveInfo, $upload_id) = @_;
    my $query = '';
    my $message = '';
    my ($newTarchiveLocation, $newTarchiveFilename,$mvTarchiveCmd);
    $message = "\nMoving tarchive into library\n";
    $this->spool($message, 'N', $upload_id, $notify_detailed);


    # ----------------------------------------------------------------
    ## Get config settings using ConfigOB
    # ----------------------------------------------------------------
    my $configOB = $this->{'configOB'};
    my $tarchivePath = $configOB->getTarchiveLibraryDir();


    # return the current tarchive location if no dates are available
    return $tarchive_location unless ($tarchiveInfo->{'DateAcquired'});

    # move the tarchive in a year subfolder
    $newTarchiveLocation = $tarchivePath ."/".
    substr($tarchiveInfo->{'DateAcquired'}, 0, 4);
    ############################################################
    ##### make the directory if it does not yet exist ##########
    ############################################################
    unless(-e $newTarchiveLocation) {
        mkdir($newTarchiveLocation, 0770);
    }
    ############################################################
    ####### determine the new name of the tarchive #############
    ############################################################
    $newTarchiveFilename = basename($tarchive_location);
    $newTarchiveLocation .= "/".$newTarchiveFilename;

    ############################################################
    ###### move the tarchive ###################################
    ############################################################
    $mvTarchiveCmd = "mv $tarchive_location $newTarchiveLocation";
    $message = "\n" . $mvTarchiveCmd . "\n";
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    `$mvTarchiveCmd`;

    ############################################################
    # now update tarchive table to store correct location ######
    ############################################################
    my $newArchiveLocationField = $newTarchiveLocation;
    $newArchiveLocationField    =~ s/$tarchivePath\/?//g;
    $query = "UPDATE tarchive ".
             " SET ArchiveLocation=" .
              ${$this->{'dbhr'}}->quote($newArchiveLocationField) .
             " WHERE DicomArchiveID=".
             ${$this->{'dbhr'}}->quote(
                $tarchiveInfo->{'DicomArchiveID'}
             );
    print $query . "\n"  if $this->{debug};
    ${$this->{'dbhr'}}->do($query);
    return $newTarchiveLocation;
}


=pod

=head3 CreateMRICandidates($subjectIDsref, $sex, $tarchiveInfo, $User, $centerID, $upload_id)

Registers a new candidate in the C<candidate> table.

Note: before doing so, the following checks will be performed:
1) check that the C<createCandidates> config option was set to yes
2) check that the C<PSCID> given in C<$subjectIDsref> is not already associated
to an existing candidate
3) check that the C<CandID> given in C<$subjectIDsref> is not already associated
to an existing candidate

INPUTS:
  - $subjectIDsref: subject's ID information hash ref
  - $sex          : sex of the candidate
  - $tarchiveInfo : tarchive information hash ref
  - $User         : user that is running the pipeline
  - $centerID     : center ID
  - upload_id     : upload ID of the study

=cut

sub CreateMRICandidates {
    ############################################################
    ### Standardize sex (DICOM uses M/F, DB uses Male/Female)
    ############################################################
    my $this  = shift;
    my ($subjectIDsref, $tarchiveInfo, $User, $centerID, $upload_id) = @_;

    my ($sex, $query, $message);
    my $dbhr   = $this->{dbhr};
    my $pscID  = $subjectIDsref->{'PSCID'};
    my $candID = $subjectIDsref->{'CandID'};

    # If there already is a candidate with that PSCID, skip the creation.
    # Note that validateCandidate (which is called later on) will validate
    # that pscid and candid match so we don't do it here.
    return if defined $pscID
        && $pscID ne 'scanner'
        && NeuroDB::MRI::subjectIDExists('PSCID', $pscID, $dbhr);

    # If there already is a candidate with that CandID, skip the creation.
    # Note that validateCandidate (which is called later on) will validate
    # that pscid and candid match so we don't do it here.
    return if NeuroDB::MRI::subjectIDExists('CandID', $candID, $dbhr);

    # return from the function if createCandidate config setting is not set
    my $configOB = $this->{'configOB'};
    return if (!$configOB->getCreateCandidates());

    # Check that a ProjectID is provided for the candidate about to be created
    if (!defined $subjectIDsref->{'ProjectID'}) {
        $message = "ERROR: Cannot create candidate $candID/$pscID as the profile file "
                 . "does not define a ProjectID for him/her.\n";
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::INSERT_FAILURE);
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);

        exit $NeuroDB::ExitCodes::INSERT_FAILURE;
    }

    $query = "SELECT ProjectID FROM Project WHERE ProjectID = ?";
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($subjectIDsref->{'ProjectID'});

    if($sth->rows != 1) {
        $message = "ERROR: Cannot create candidate $pscID with ProjectID "
                 . "$subjectIDsref->{'ProjectID'}: that project ID is invalid.\n";
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::INSERT_FAILURE);
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);

        exit $NeuroDB::ExitCodes::INSERT_FAILURE;
    }

    # Create non-existent candidate if the profile allows for Candidate creation
    if ($tarchiveInfo->{'PatientSex'} eq 'F') {
        $sex = "Female";
    } elsif ($tarchiveInfo->{'PatientSex'} eq 'M') {
        $sex = "Male";
    }

    chomp($User);
    $candID = NeuroDB::MRI::createNewCandID($dbhr) unless $candID;
    my %record = (
        CandID                => $subjectIDsref->{'CandID'},
        PSCID                 => $subjectIDsref->{'PSCID'},
        DoB                   => $subjectIDsref->{'PatientDoB'},
        Sex                   => $sex,
        RegistrationCenterID  => $centerID,
        RegistrationProjectID => $subjectIDsref->{'ProjectID'},
        UserID                => $User,
    );

    $query = sprintf(
        "INSERT INTO candidate (%s) VALUES (%s)",
        join(',', keys %record)         . ',Date_active,Date_registered,Entity_type',
        join(',', ('?') x keys %record) . ",NOW()      ,NOW()          ,'Human'"
    );

    print "$query\n" if ($this->{debug});
    $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute(values %record);

    $message = "\n==> CREATED NEW CANDIDATE: $candID";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
}


=pod

=head3 validateArchive($tarchive, $tarchiveInfo, $upload_id)

Validates the DICOM archive by comparing the MD5 of the C<$tarchive file> and
the one stored in the tarchive information hash ref C<$tarchiveInfo> derived
from the database. The function will exits with an error message if the
DICOM archive is not validated.

INPUTS:
  - $tarchive    : DICOM archive file
  - $tarchiveInfo: DICOM archive information hash ref
  - $upload_id   : upload ID of the study

=cut

sub validateArchive {
    my $this = shift;
    my ($tarchive, $tarchiveInfo, $upload_id) = @_;

    my $message = "\n==> verifying dicom archive md5sum (checksum)\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    my $cmd = "md5sum $tarchive";
    if ($this->{verbose})  {
        print $cmd . "\n";
    }
    my $md5_check = `$cmd`;
    my ($md5_real, $real) = split(' ', $md5_check);
    my ($md5_db  , $db)   = split(' ', $tarchiveInfo->{'md5sumArchive'});
    $message = "\n-> checksum for target        :  ".
        "$md5_real\n-> checksum from database :  $md5_db\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    if ($md5_real ne $md5_db) {
        $message =  "\nerror: archive seems to be corrupted or modified. ".
                       "upload will exit now.\nplease read the creation logs ".
                       " for more  information!\n\n";
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::CORRUPTED_FILE);
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);
        exit $NeuroDB::ExitCodes::CORRUPTED_FILE;
    }
}




=pod

=head3 validate_tarchive_id_against_upload_id($tarchiveInfoRef, $uploadInfoRef)

INPUTS:
  - $tarchiveInfoRef: DICOM archive information hash ref
  - $uploadInfoRef  : MRI upload information reference

=cut

sub validate_tarchive_id_against_upload_id {
    my $this = shift;
    my ($tarchiveInfoRef, $uploadInfoRef) = @_;

    my $upload_id        = $uploadInfoRef->{'UploadID'};
    my $archive_location = $tarchiveInfoRef->{'ArchiveLocation'};
    my $tarchive_id_mu   = $uploadInfoRef->{'TarchiveID'};
    my $tarchive_id_t    = $tarchiveInfoRef->{'TarchiveID'};

    unless ($tarchiveInfoRef->{'TarchiveID'} == $uploadInfoRef->{'TarchiveID'}) {
        my $message = "\nERROR: UploadID {$upload_id} is associated with TarchiveID {$tarchive_id_mu}"
                      . " while ArchiveLocation {$archive_location} is associated with TarchiveID {$tarchive_id_t}."
                      . " Please, ensure the arguments provided to the script refer to the same tarchive\n\n";
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::CORRUPTED_FILE);
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);
        exit $NeuroDB::ExitCodes::CORRUPTED_FILE;
    }
}


=pod

=head3 which_directory($subjectIDsref, $data_dir, $hrrt)

Determines where the MINC files to be registered into the database will go.

INPUTS:
   - $subjectIDsref: subject's ID information hashref
   - $data_dir     : data directory (e.g. C</data/$PROJECT/data>)
   - $hrrt         : boolean, whether the file comes from a PET HRRT scanner

RETURNS: the final directory in which the registered MINC files will go
(typically C</data/$PROJECT/data/assembly/CandID/visit/mri/>)

=cut

sub which_directory {
    my $this = shift;
    my ( $subjectIDsref, $data_dir, $hrrt ) = @_;
    my %subjectIDs = %$subjectIDsref;
    my $dir = $data_dir;
    $dir = "$dir/assembly/$subjectIDs{'CandID'}/$subjectIDs{'visitLabel'}";
    $dir =~ s/ //;
    $dir .= $hrrt ? "/pet" : "/mri";
    return $dir;
}


=pod

=head3 validateCandidate($subjectIDsref, $upload_id)

Check that the candidate's information derived from the patient name field of
the DICOM files is valid (C<CandID> and C<PSCID> of the candidate should
correspond to the same subject in the database). It will also check that the
Visit Label of C<$subjectIDsref> is a valid Visit Label present in the
C<Visit_Windows> table.

INPUT: subject's ID information hash ref

RETURNS: the candidate mismatch error, or undef if the candidate is validated
or a phantom

=cut

sub validateCandidate {
    my $this = shift;
    my ($subjectIDsref, $upload_id) = @_;

    my ($CandMismatchError, $message);
    my $pscID       = $subjectIDsref->{'PSCID'};
    my $candID      = $subjectIDsref->{'CandID'};
    my $visit_label = $subjectIDsref->{'visitLabel'};
    my $dbh         = ${$this->{'dbhr'}};

    # --------------------------------------------------
    ## No further checking if the subject is Phantom
    # --------------------------------------------------

    return undef if ($subjectIDsref->{'isPhantom'});



    # --------------------------------------------------
    ### Check that the CandID and PSCID are valid
    # --------------------------------------------------

    my $query = "SELECT c1.CandID, c2.PSCID "
        . " FROM candidate c1 "
        . " LEFT JOIN candidate c2 ON (c1.CandID=c2.CandID AND c2.PSCID=?) "
        . " WHERE c1.CandID=? ";
    my $sth   = $dbh->prepare($query);
    $sth->execute($pscID, $candID);
    my $results = $sth->fetchrow_hashref();

    if (!$results) {

        # if no rows were returned, then the CandID is not valid
        $message = "\n\n=> Could not find candidate with CandID=$candID in database\n";
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::INSERT_FAILURE);
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);

        return 'CandID does not exist';

    } elsif (!$results->{'PSCID'}) {

        # if no PSCID returned in the row, then PSCID and CandID do not match
        $message = "PSCID and CandID of the image mismatch\n";
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::INSERT_FAILURE);
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);

        return $message;
    }




    # --------------------------------------------------
    ### Check if visit label is valid
    # --------------------------------------------------

    $query = "SELECT Visit_label FROM Visit_Windows WHERE BINARY Visit_label=?";
    my @rows = $dbh->selectall_array($query, {}, $visit_label);

    # return undef if a row was returned from Visit_Windows with this visit label
    # which means that the visit label is valid and there is nothing else to check.
    return undef if (scalar @rows > 0);

    # if we end up here, it means that the visit label was not found in Visit_Windows
    # therefore need to check if 'createVisitLabel' was set
    if ($subjectIDsref->{'createVisitLabel'}) {

        $message = "\n=> Will create visit label $visit_label in Visit_Windows\n";

    } else {

        $message = "\n=> No Visit label\n";
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::INSERT_FAILURE);

        return "Visit label $visit_label does not exist in Visit_Windows";

    }

    # write the message about the visit label in the notification spool table
    $this->spool($message, 'Y', $upload_id, $notify_notsummary);



    # if we ended up here, then the candidate is validated and the function
    # returns no candidate mismatch error.
    return undef;
}


=pod

=head3 computeSNR($tarchiveID, $upload_id)

Computes the SNR on the modalities specified in the Config module under the
section Imaging Pipeline in the field called 'compute_snr_modalities'.

INPUTS:
  - $tarchiveID: DICOM archive ID
  - $upload_id : upload ID of the study

=cut

sub computeSNR {

    my $this = shift;
    my ($tarchiveID, $upload_id) = @_;


    # ----------------------------------------------------------------
    ## Get config settings using ConfigOB
    # ----------------------------------------------------------------
    my $configOB = $this->{'configOB'};
    my $data_dir   = $configOB->getDataDirPath();
    my @modalities = $configOB->getComputeSnrModalities();

    (my $query = <<QUERY) =~ s/\n//gm;
  SELECT    FileID, File, mst.MriScanTypeName AS ScanType
  FROM      files f
  JOIN      mri_scan_type mst ON (mst.MriScanTypeID=f.MriScanTypeID)
  WHERE     f.TarchiveSource=?
QUERY
    print $query . "\n" if ($this->{debug});
    my $minc_file_arr = ${$this->{'dbhr'}}->prepare($query);
    $minc_file_arr->execute($tarchiveID);
    while (my $row = $minc_file_arr->fetchrow_hashref()) {
        my $filename     = $row->{'File'};
        my $fileID       = $row->{'FileID'};
        my $fileScanType = $row->{'ScanType'};
        my $base         = basename($filename);
        my $fullpath     = "$data_dir/$filename";
        my $message;
        if (@modalities && grep($_ eq $fileScanType, @modalities) ) {
            my $cmd = "noise_estimate --snr $fullpath";
            my $SNR = `$cmd`;
            $SNR =~ s/\n//g;
            print "$cmd \nSNR is: $SNR \n" if ($this->{verbose});
            my $file = NeuroDB::File->new($this->{dbhr});
            $file->loadFile($fileID);
            my $SNR_old = $file->getParameter('SNR');
            if ($SNR ne '') {
                $file->setParameter('SNR', $SNR);
                if (defined($SNR_old) && $SNR_old ne '' && $SNR_old ne $SNR) {
                    $message = "The SNR value was updated from $SNR_old to $SNR.\n";
                    $this->{LOG}->print($message);
                    $this->spool($message, 'N', $upload_id, $notify_detailed);
                }
            }
        } else {
            $message = "The SNR can not be computed for $base as the imaging "
                       . "modality is not supported by the SNR computation. ";
            $message .= @modalities
                ? sprintf(
                    "The supported modalities for your projects are: %s.\n",
                    join(', ', @modalities)
                  )
                : "There are no supported modalities for your projects.\n";
            $this->{LOG}->print($message);
            $this->spool($message, 'N', $upload_id, $notify_detailed);
        }
    }
}


=pod

=head3 orderModalitiesByAcq($tarchiveID, $upload_id)

Order imaging modalities by acquisition number.

INPUTS:
  - $tarchiveID: DICOM archive ID
  - $uploadID  : upload ID of the study

=cut

sub orderModalitiesByAcq {

    my $this = shift;
    my ($file, $acqProtID, $dataArr, $message, $sth);
    my ($tarchiveID, $upload_id)= @_;

    my $queryAcqProt = "SELECT DISTINCT f.MriScanTypeID ".
                        "FROM files f ".
                        "WHERE f.TarchiveSource=?";

    if ($this->{debug}) {
        print $queryAcqProt . "\n";
    }

    my $acqArr = ${$this->{'dbhr'}}->prepare($queryAcqProt);
    $acqArr->execute($tarchiveID);
    # For each of the files having this MriScanTypeID
    # load the file object to get the series_number
    while (my $rowAcqProt = $acqArr->fetchrow_hashref()) {
        $acqProtID = $rowAcqProt->{'MriScanTypeID'};
        my $queryDataArr = "SELECT f.FileID, f.AcqOrderPerModality ".
                            "FROM files f ".
                            "WHERE f.TarchiveSource=? AND f.MriScanTypeID=?";

        if ($this->{debug}) {
            print $queryDataArr . "\n";
        }

        $dataArr = ${$this->{'dbhr'}}->prepare($queryDataArr);
        $dataArr->execute($tarchiveID, $acqProtID);
        my (@fileIDArr, @seriesNumberArr)=();
        my $i=0;
        while (my $rowDataArr = $dataArr->fetchrow_hashref()) {
            $fileIDArr[$i] = $rowDataArr->{'FileID'};
            $file = NeuroDB::File->new($this->{dbhr});
            $file->loadFile($fileIDArr[$i]);
            $seriesNumberArr[$i] = $file->getParameter('series_number');
            $i++;
        }
        my (@sorted_seriesNumber_indices, @sorted_fileIDArr)=();
        # Sort the series_number, and assign the Modality Order accordingly
        @sorted_seriesNumber_indices = sort {$seriesNumberArr[$a] <=> $seriesNumberArr[$b]} (0..$#seriesNumberArr);
        @sorted_fileIDArr = @fileIDArr[@sorted_seriesNumber_indices];

        my $order = 1;
        foreach my $j (0..$#seriesNumberArr) {
            my $update = "UPDATE files f SET f.AcqOrderPerModality=? ".
                         "WHERE f.FileID=?";
            if ($this->{debug}) {
                print $update . "\n";
            }
            my $modalityOrder_update = ${$this->{'dbhr'}}->prepare($update);
            $modalityOrder_update->execute($order, $sorted_fileIDArr[$j]);
            $message = "The Modality Order for FileID $sorted_fileIDArr[$j] was updated to $order \n ";
            $this->{LOG}->print($message);
            $this->spool($message, 'N', $upload_id, $notify_detailed);
            $order++;
        }
    }
}

=pod

=head3 getUploadIDUsingTarchiveSrcLoc($tarchive_srcloc)

Gets the upload ID form the C<mri_upload> table using the DICOM archive
C<SourceLocation> specified in the C<tarchive> table.

INPUT: DICOM archive's source location

RETURNS: the found upload ID

=cut


sub getUploadIDUsingTarchiveSrcLoc {

    ############################################################
    ################ Establish database connection #############
    ############################################################
    my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

    my $tarchive_srcloc = shift;
    my $query = '';
    my $upload_id = undef;

    if ($tarchive_srcloc) {
        ########################################################
        ###Extract upload_id using tarchive source location#####
        ########################################################
    $query = "SELECT UploadID FROM mri_upload "
            . "WHERE DecompressedLocation =?";
    my $sth = $dbh->prepare($query);
        $sth->execute($tarchive_srcloc);
        if ( $sth->rows > 0 ) {
           $upload_id = $sth->fetchrow_array;
        }
    }
    return $upload_id;
}


=pod

=head3 spool($message, $error, $upload_id, $verb)

Calls the C<Notify->spool> function to log all messages.

INPUTS:
  - $message   : message to be logged in the database
  - $error     : 'Y' for an error log,
                 'N' otherwise
  - $upload_id : the upload ID
  - $verb      : 'N' for few main messages,
                 'Y' for more messages (developers)

=cut

sub spool  {
    my $this = shift;
    my ( $message, $error, $upload_id, $verb ) = @_;

    if ($error eq 'Y'){
    print "Spool message is: $message \n";
    }
    $this->{'Notify'}->spool('mri upload processing class', $message, 0,
           'MRIProcessingUtility.pm', $upload_id, $error, $verb);
}


=pod

=head3 is_file_unique($file, $upload_id)

Queries the C<files> and C<parameter_file> tables to make sure that no imaging
datasets with the same C<SeriesUID>, C<EchoTime>, C<EchoNumber> and
C<PhaseEncodingDirection> or the same C<MD5sum> hash can be found in the database
already. If there is a match, it will return a message with the information about
why the file is not unique. If there is no match, then it will return undef.

INPUTS:
  - $file     : the file object from the C<NeuroDB::File> package
  - $upload_id: the C<UploadID> associated to the file

RETURNS: a message with the reason why the file is not unique or undef

=cut

sub is_file_unique {

    my $this = shift;
    my ($file, $upload_id) = @_;

    my $seriesUID     = $file->getParameter('series_instance_uid');
    my $echo_time     = $file->getParameter('echo_time');
    my $phase_enc_dir = $file->getParameter('phase_encoding_direction');
    my $echo_number   = $file->getParameter('echo_numbers');

    # check that no files are already in the files table with the same SeriesUID
    # and EchoTime
    my $query     = "SELECT File FROM files WHERE "
                    . " SeriesUID = ?  AND EchoTime = ? AND "
                    . " EchoNumber = ? AND PhaseEncodingDirection=?";
    my $sth       = ${$this->{'dbhr'}}->prepare( $query );
    $sth->execute( $seriesUID, $echo_time, $echo_number, $phase_enc_dir );
    my $results = $sth->fetchrow_array;
    my $message;
    if (defined $results) {
        $message = "\n--> ERROR: there is already a file registered in the files "
                   . "table with SeriesUID='$seriesUID', EchoTime='$echo_time', "
                   . "EchoNumber='$echo_number' and PhaseEncodingDirection='$phase_enc_dir.\n"
                   . "\tThe already registered file is '$results'\n";
        return $message;
    }

    # compute the MD5sum
    my $unique = $this->computeMd5Hash( $file, $upload_id );
    if (!$unique) {
        my $filename = $file->getFileDatum( 'File'    );
        my $md5hash  = $file->getParameter( 'md5hash' );
        $message  = "\n--> ERROR: there is already a file registered in the files "
                   . "table with the same MD5 hash ($md5hash) as '$filename'.\n";
        return $message;
    }

    return undef;
}


1;


=pod

=head1 TO DO

Document the following functions:
  - concat_mri($minc_files)
  - registerProgs(@toregister)

Remove the function get_acqusitions($study_dir, \@acquisitions) that is not used

Fix comments written as #fixme in the code

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

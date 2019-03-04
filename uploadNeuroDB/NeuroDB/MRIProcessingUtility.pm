package NeuroDB::MRIProcessingUtility;


=pod

=head1 NAME

NeuroDB::MRIProcessingUtility -- Provides an interface for MRI processing
utilities

=head1 SYNOPSIS

  use NeuroDB::ProcessingUtility;

  my $utility       = NeuroDB::MRIProcessingUtility->new(
                        \$dbh,    $debug,  $TmpDir,
                        $logfile, $LogDir, $verbose
                      );

  %tarchiveInfo     = $utility->createTarchiveArray(
                        $ArchiveLocation, $globArchiveLocation
                      );

  my ($center_name, $centerID) = $utility->determinePSC(\%tarchiveInfo,0);

  my $scannerID     = $utility->determineScannerID(
                        \%tarchiveInfo, 0,
                        $centerID,      $NewScanner
                      );

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
use Path::Class;


## Define Constants ##
my $notify_detailed   = 'Y'; # notification_spool message flag for messages to be displayed 
                             # with DETAILED OPTION in the front-end/imaging_uploader 
my $notify_notsummary = 'N'; # notification_spool message flag for messages to be displayed 
                             # with SUMMARY Option in the front-end/imaging_uploader 


=pod

=head3 new($dbhr, $debug, $TmpDir, $logfile, $verbose) >> (constructor)

Creates a new instance of this class. The parameter C<$dbhr> is a reference
to a C<DBI> database handle, used to set the object's database handle, so that
all the DB-driven methods will work.

INPUT: C<DBI> database handle

RETURNS: new instance of this class.

=cut

sub new {
    my $params = shift;
    my ($dbhr,$debug,$TmpDir,$logfile,$verbose) = @_;
    unless(defined $dbhr) {
       croak(
           "Usage: ".$params."->new(\$databaseHandleReference)"
       );
    }
    my $self = {};

    ############################################################
    ############### Create a settings package ##################
    ############################################################
    my $profile = "prod";
    {
     package Settings;
     do "$ENV{LORIS_CONFIG}/.loris_mri/$profile";
    }

    ############################################################
    #### Create the log file and a Notify Object################
    ############################################################
    my $LogDir  = dirname($logfile);
    my $file_name = basename($logfile);
    my $dir = dir($LogDir);
    my $file = $dir->file($file_name);
    my $LOG = $file->openw();
    my $Notify = NeuroDB::Notify->new( $dbhr );
    $LOG->autoflush(1);
    $self->{'Notify'} = $Notify;
    $self->{'LOG'} = $LOG;
    $self->{'verbose'} = $verbose;
    $self->{'LogDir'} = $LogDir;
    $self->{'dbhr'} = $dbhr;
    $self->{'debug'} = $debug;
    $self->{'TmpDir'} = $TmpDir;
    $self->{'logfile'} = $logfile;
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
    my ($message, $failStatus,$LogDir) = @_;
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

=head3 determineSubjectID($scannerID, $tarchiveInfo, $to_log, $upload_id)

Determines subject's ID based on scanner ID and DICOM archive information.

INPUTS:
  - $scannerID   : scanner ID,
  - $tarchiveInfo: DICOM archive information hash ref,
  - $to_log      : boolean if this step should be logged
  - $upload_id   : upload ID of the study

RETURNS: subject's ID hash ref containing C<CandID>, C<PSCID> and Visit Label
information

=cut

sub determineSubjectID {

    my $this = shift;
    my ($scannerID,$tarchiveInfo,$to_log, $upload_id) = @_;
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
    my $subjectIDsref = Settings::getSubjectIDs(
                            $tarchiveInfo->{'PatientName'},
                            $tarchiveInfo->{'PatientID'},
                            $scannerID,
                            $this->{dbhr}
                        );
    if ($to_log) {
        my $message = sprintf(
            "\n==> Data found for candidate CandID: %s, PSCID %s, Visit %s, Acquisition Date %s\n ",
            $subjectIDsref->{'CandID'},
            $subjectIDsref->{'PSCID'},
            $subjectIDsref->{'visitLabel'},
            $tarchiveInfo->{'DateAcquired'} // 'UNKNOWN'
        );
	$this->{LOG}->print($message);
        $this->spool($message, 'N', $upload_id, $notify_detailed);
    }
    return $subjectIDsref;
}


=pod

=head3 createTarchiveArray($tarchive, $globArchiveLocation)

Creates the DICOM archive information hash ref.

INPUTS:
  - $tarchive           : tarchive's path
  - $globArchiveLocation: globArchiveLocation argument specified when running
                           the insertion scripts

RETURNS: DICOM archive information hash ref

=cut

sub createTarchiveArray {

    my $this = shift;
    my %tarchiveInfo;
    my ($tarchive,$globArchiveLocation) = @_;
    my $where = "ArchiveLocation='$tarchive'";
    if ($globArchiveLocation) {
        $where = "ArchiveLocation LIKE '%".basename($tarchive)."'";
    }
    my $query = "SELECT PatientName, PatientID, PatientDoB, md5sumArchive,".
                " DateAcquired, DicomArchiveID, PatientGender,".
                " ScannerManufacturer, ScannerModel, ScannerSerialNumber,".
                " ScannerSoftwareVersion, neurodbCenterName, TarchiveID,".
                " SourceLocation, ArchiveLocation FROM tarchive WHERE $where";
    if ($this->{debug}) {
        print $query . "\n";
    }
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();

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
    my $lookupCenterNameUsing = NeuroDB::DBI::getConfigSetting(
                        $this->{dbhr},'lookupCenterNameUsing'
                        );
    my ($center_name, $centerID) =
    NeuroDB::MRI::getPSC(
        $tarchiveInfo->{$lookupCenterNameUsing},
        $this->{dbhr}
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
        my $message =
            "\n==> Verifying acquisition center\n-> " .
            "Center Name : $center_name\n-> CenterID ".
            " : $centerID\n";
	$this->{LOG}->print($message);
	$this->spool($message, 'N', $upload_id, $notify_detailed);
    }
    return ($center_name, $centerID);
}


=pod

=head3 determineScannerID($tarchiveInfo, $to_log, $centerID, $NewScanner, $upload_id)

Determines which scanner ID was used for DICOM acquisitions.

INPUTS:
  - $tarchiveInfo: archive information hash ref
  - $to_log      : whether this step should be logged
  - $centerID    : center ID
  - $NewScanner  : whether a new scanner entry should be created if the scanner
                   used is a new scanner for the study
  - $upload_id   : upload ID of the study

RETURNS: scanner ID

=cut

sub determineScannerID {

    my $this = shift;
    my ($tarchiveInfo, $to_log, $centerID, $NewScanner, $upload_id) = @_;
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
            $this->{dbhr},
            $NewScanner 
        );
    if ($scannerID == 0) {
        if ($to_log) {
            $message = "\nERROR: The ScannerID for this particular scanner ".
                          "does not exist. Enable creating new ScannerIDs in ".
                          "your profile or this archive can not be ".
                          "uploaded.\n\n";
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

=head3 getAcquisitionProtocol($file, $subjectIDsref, $tarchiveInfo, $center_name, $minc, $acquisitionProtocol, $bypass_extra_file_checks, $upload_id)

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
  - $center_name             : center name
  - $minc                    : absolute path to the MINC file
  - $acquisitionProtocol     : acquisition protocol if already knows it
  - $bypass_extra_file_checks: boolean, if set bypass the extra checks
  - $upload_id               : upload ID of the study

RETURNS:
  - $acquisitionProtocol     : acquisition protocol
  - $acquisitionProtocolID   : acquisition protocol ID
  - $extra_validation_status : extra validation status ("pass", "exclude", "warning")

=cut

sub getAcquisitionProtocol {
   
    my $this = shift;
    my ($file,$subjectIDsref,$tarchiveInfoRef,$center_name,$minc,
        $acquisitionProtocol,$bypass_extra_file_checks, $upload_id) = @_;
    my $message = '';

    ############################################################
    ## get acquisition protocol (identify the volume) ##########
    ############################################################

    if(!defined($acquisitionProtocol)) {
      $message = "\n==> verifying acquisition protocol\n";
      $this->{LOG}->print($message);
      $this->spool($message, 'N', $upload_id, $notify_detailed);

      $acquisitionProtocol =  &NeuroDB::MRI::identify_scan_db(
                                   $center_name,
                                   $subjectIDsref,
                                   $tarchiveInfoRef,
                                   $file, 
                                   $this->{dbhr}, 
                                   $minc
                                 );
    }

    $message = "\nAcquisition protocol is $acquisitionProtocol\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);

    my $extra_validation_status;
    my $acquisitionProtocolID;
    if ($acquisitionProtocol !~ /unknown/) {
        $acquisitionProtocolID =
        &NeuroDB::MRI::scan_type_text_to_id(
          $acquisitionProtocol, $this->{dbhr}
        );

        if ($bypass_extra_file_checks == 0) {
            $extra_validation_status = $this->extra_file_checks(
                        $acquisitionProtocolID, 
                        $file, 
                        $subjectIDsref->{'CandID'}, 
                        $subjectIDsref->{'visitLabel'},
                        $tarchiveInfoRef->{'PatientName'}
                    );
          $message = "\nextra_file_checks from table mri_protocol_check " .
                     "logged in table mri_violations_log: $extra_validation_status\n";
	  $this->{LOG}->print($message);
	  # 'warn' and 'exclude' are errors, while 'pass' is not
	  # log in the notification_spool_table the $Verbose flag accordingly
	  if ($extra_validation_status ne 'pass'){
	          $this->spool($message, 'Y', $upload_id, $notify_notsummary);
	  }
	  else{
	          $this->spool($message, 'N', $upload_id, $notify_detailed);
	  }
        }
    }
    return ($acquisitionProtocol, $acquisitionProtocolID, $extra_validation_status);
}


=pod

=head3 extra_file_checks($scan_type, $file, $CandID, $Visit_Label, $PatientName)

Returns the list of MRI protocol checks that failed. Can't directly insert
this information here since the file isn't registered in the database yet.

INPUTS:
  - $scan_type  : scan type of the file
  - $file       : file information hash ref
  - $CandID     : candidate's C<CandID>
  - $Visit_Label: visit label of the scan
  - $PatientName: patient name of the scan

RETURNS:
  - pass, warn or exclude flag depending on the worst failed check
  - array of failed checks if any were failed

=cut

sub extra_file_checks() {
      
    my $this        = shift;
    my $scan_type   = shift;
    my $file        = shift;
    my $candID      = shift;
    my $visit_label = shift;
    my $pname       = shift;

    ## Step 1 - select all distinct exclude and warning headers for the scan type
    my $query = "SELECT DISTINCT(Header) FROM mri_protocol_checks "
                . "WHERE Scan_type=? AND Severity=?";
    my $sth   = ${$this->{'dbhr'}}->prepare($query);
    if ($this->{debug}) {
        print $query . "\n";
    }

    # Step 2 - loop through all severities and grep headers, valid fields and
    # check if the scan is valid. If the scan is not valid, then, return the
    # severity of the failure.
    foreach my $severity (qw/exclude warning/) {
        $sth->execute($scan_type, $severity);
        my @headers = map { $_->{'Header'} } @{ $sth->fetchall_arrayref({}) };
        my %validFields = $this->loop_through_protocol_violations_checks(
            $scan_type, $severity, \@headers, $file
        );
        if (%validFields) {
            $this->insert_into_mri_violations_log(
                \%validFields, $severity, $pname, $candID, $visit_label, $file
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

    my $seriesUID = $file_ref->getParameter('series_instance_uid');
    my $file_path = $file_ref->getFileDatum('File');

    # TODO: in a different PR, should add the echo time to the mri_violation table
    # TODO: and add the echo time in the where part of the statement
    my $query = "UPDATE mri_violations_log SET MincFile = ? WHERE SeriesUID = ?";
    my $sth   = ${$this->{'dbhr'}}->prepare($query);

    $sth->execute($file_path, $seriesUID);
}


=pod

=head3 loop_through_protocol_violations_checks($scan_type, $severity, $headers, $file)

Loops through all protocol violations checks for a given severity and creates
a hash with all the checks that need to be applied on that specific scan type
and severity.

INPUTS:
  - $scan_type: scan type of the file
  - $severity : severity of the checks we want to loop through (exclude or warning)
  - $headers  : list of different headers found in the C<mri_protocol_checks>
                table for a given scan type
  - $file     : file information hash ref

RETURNS: a hash with all information about the checks for a given scan type
and severity

=cut

sub loop_through_protocol_violations_checks {
    my ($this, $scan_type, $severity, $headers, $file) = @_;

    my %valid_fields; # will store all information about what fails

    # query to fetch list of valid protocols in mri_protocol_checks table
    my $query = "SELECT * FROM mri_protocol_checks "
                . "WHERE Scan_type=? AND Severity=? AND Header=?";
    my $sth   = ${$this->{'dbhr'}}->prepare($query);

    # loop through all severity headers for the scan type and check if in the
    # value of the header in the file fits one of the valid range present in
    # mri_protocol_checks
    foreach my $header (@$headers) {
        # get the value from the file
        my $value = $file->getParameter($header);

        # execute query for $scan_type, $severity, $header
        $sth->execute($scan_type, $severity, $header);

        # grep all valid ranges and regex to compare with value in the file
        my @rows = @{ $sth->fetchall_arrayref(
            { ValidRange => 1, ValidRegex => 1 }
        ) };
        my @valid_ranges = grep($_->{'ValidRange'}, @rows);
        my @valid_regexs = grep($_->{'ValidRegex'}, @rows);

        # go to the next header if did not find any checks for that scan
        # type, severity and header
        next if (!@valid_ranges && !@valid_regexs);

        # loop through all checks
        next if grep(NeuroDB::MRI::in_range($value, $_->{'ValidRange'}), @valid_ranges);
        next if grep($value =~ /$_->{'ValidRegex'}/, @valid_regexs);

        $valid_fields{$header} = {
            ScanType    => $scan_type,
            HeaderValue => $value,
            ValidRanges => [ map { $_->{'ValidRange'} } @valid_ranges ],
            ValidRegexs => [ map { $_->{'ValidRegex'} } @valid_regexs ]
        };
    }

    return %valid_fields;
}

=pod

=head3 insert_into_mri_violations_log($valid_fields, $severity, $pname, $candID, $visit_label, $file)

For a given protocol failure, it will insert into the C<mri_violations_log>
table all the information about the scan and the protocol violation.

INPUTS:
  - $valid_fields: string with valid values for the header and scan type
  - $severity    : severity of the violation ("exclude" or "warning")
  - $pname       : Patient name associated with the scan
  - $candID      : C<CandID> associated with the scan
  - $visit_label : visit label associated with the scan
  - $file        : information about the scan

=cut

sub insert_into_mri_violations_log {
    my ($this, $valid_fields, $severity, $pname, $candID, $visit_label, $file) = @_;

    # determine the future relative path when the file will be moved to
    # data_dir/trashbin at the end of the script's execution
    my $file_path     = $file->getFileDatum('File');
    my $file_rel_path = NeuroDB::MRI::get_trashbin_file_rel_path($file_path);

    my $query = "INSERT INTO mri_violations_log"
                    . "("
                    . "SeriesUID, TarchiveID,  MincFile,   PatientName, "
                    . " CandID,   Visit_label, Scan_type,  Severity, "
                    . " Header,   Value,       ValidRange, ValidRegex "
                    . ") VALUES ("
                    . " ?,        ?,           ?,          ?, "
                    . " ?,        ?,           ?,          ?, "
                    . " ?,        ?,           ?,          ? "
                    . ")";
    if ($this->{debug}) {
        print $query . "\n";
    }
    my $sth = ${$this->{'dbhr'}}->prepare($query);

    # foreach header, concatenate arrays of ranges into a string
    foreach my $header (keys(%$valid_fields)) {
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
        $file->setFileData('Caveat', 1) if ($severity eq 'warning');

        $sth->execute(
            $file->getFileDatum('SeriesUID'),
            $file->getFileDatum('TarchiveSource'),
            $file_rel_path,
            $pname,
            $candID,
            $visit_label,
            $valid_fields->{$header}{ScanType},
            $severity,
            $header,
            $valid_fields->{$header}{HeaderValue},
            $valid_range_str,
            $valid_regex_str
        );
    }
}



=pod

=head3 update_mri_acquisition_dates($sessionID, $acq_date)

Updates the C<mri_acquisition_dates> table by a new acquisition date
C<$acq_date>.

INPUTS:
  - $sessionID: session ID
  - $acq_date : acquisition date

=cut

sub update_mri_acquisition_dates {
   
    my $this = shift;
    my ($sessionID, $acq_date) = @_;

    #####################################################################
    # set acquisition date to undef if the date is '0000-00-00', '' or 0
    #####################################################################
    if ( defined $acq_date
            && ($acq_date eq '0000-00-00' || $acq_date eq '' || $acq_date == 0) ) {
        $acq_date = undef;
    }

    #######################################################
    # get the registered acquisition date for this session
    #######################################################
    my $query = "SELECT s.ID, m.AcquisitionDate "
                . " FROM session AS s "
                . " LEFT OUTER JOIN mri_acquisition_dates AS m ON (s.ID=m.SessionID)"
                . " WHERE s.ID = ? AND s.Active = 'Y'";

    if ($acq_date) {
        $query .= " AND (m.AcquisitionDate > ? OR m.AcquisitionDate IS NULL)";
    } else {
        $query .= " AND m.AcquisitionDate IS NULL";
    }

    print "$query\n" if ($this->{debug});

    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($sessionID, $acq_date);

    ################################################################################
    # if we found a session, it needs updating or inserting, so we use replace into
    ################################################################################
    if ($sth->rows > 0) {
        $query = "REPLACE INTO mri_acquisition_dates".
                    " SET AcquisitionDate=?, SessionID=?";
        $sth = ${$this->{'dbhr'}}->prepare($query);
        $sth->execute($acq_date, $sessionID);
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
    $message = 	"\n==> Loading file from disk $minc\n";
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

=head3 move_minc($minc, $subjectIDsref, $minc_type, $fileref, $prefix, $data_dir, $tarchive_srcloc, $upload_id)

Renames and moves the MINC file.

INPUTS:
  - $minc           : path to the MINC file
  - $subjectIDsref  : subject's ID hash ref
  - $minc_type      : MINC file information hash ref
  - $fileref        : file information hash ref
  - $prefix         : study prefix
  - $data_dir       : data directory (e.g. C</data/$PROJECT/data>)
  - $tarchive_srcloc: DICOM archive source location
  - $upload_id      : upload ID of the study

RETURNS: new name of the MINC file with path relative to C<$data_dir>

=cut

sub move_minc {
    
    my $this = shift;
    my ($minc,$subjectIDsref, $minc_type, $fileref,
		$prefix,$data_dir, $upload_id) = @_;
    my ($new_name, $version,$cmd,$new_dir,$extension,@exts,$dir);
    my $concat = "";
    my $message = '';

    ############################################################
    ### figure out where to put the files ######################
    ############################################################
    $dir = $this->which_directory($subjectIDsref,$data_dir);
    `mkdir -p -m 770 $dir/native`;

    ############################################################
    ####### figure out what to call files ######################
    ############################################################
    @exts = split(/\./, basename($$minc));
    shift @exts;
    $extension = join('.', @exts);
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

=head3 registerScanIntoDB($minc_file, $tarchiveInfo, $subjectIDsref, $acquisitionProtocol, $minc, $extra_validation_status, $reckless, $sessionID, $upload_id)

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

RETURNS: acquisition protocol ID of the MINC file

=cut

sub registerScanIntoDB {

    my $this = shift;
    my (
        $minc_file, $tarchiveInfo,$subjectIDsref,$acquisitionProtocol, 
        $minc, $extra_validation_status,$reckless, $sessionID, $upload_id
    ) = @_;

    my $data_dir = NeuroDB::DBI::getConfigSetting(
                        $this->{dbhr},'dataDirBasepath'
                        );
    my $prefix = NeuroDB::DBI::getConfigSetting(
                        $this->{dbhr},'prefix'
                        );

    my $acquisitionProtocolID = undef;
    my (
        $Date_taken,$minc_protocol_identified,
        $file_path,$tarchive_path,$fileID
    );
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
        ) && $extra_validation_status !~ /exclude/) {

        ########################################################
        # convert the textual scan_type into the scan_type id ##
        ########################################################
        $acquisitionProtocolID = NeuroDB::MRI::scan_type_text_to_id(
                                        $acquisitionProtocol, 
                                        $this->{dbhr}
                                 );
        $${minc_file}->setFileData(
            'AcquisitionProtocolID', 
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
                                        \$minc,
                                        $subjectIDsref,
                                        $acquisitionProtocol,
                                        $minc_file,
                                        $prefix,
                                        $data_dir,
                                        $upload_id
                                     );

        ########################################################
        #################### set the new file_path #############
        ######################################################## 
        $file_path   =   $minc;
        $file_path      =~  s/$data_dir\///i;
        $${minc_file}->setFileData(
            'File', 
            $file_path
        );

        ########################################################
        ### record which tarchive was used to make this file ###
        ########################################################
        $tarchive_path = $tarchiveInfo->{ArchiveLocation};
        if ($tarchive_path) {
            $tarchive_path =~ s/$data_dir\///i;
            $${minc_file}->setParameter('tarchiveLocation', $tarchive_path);
            $${minc_file}->setParameter(
                'tarchiveMD5', $tarchiveInfo->{'md5sumArchive'}
            );
        }

        ########################################################
        # register into the db fixme if I ever want a dry run ## 
        ########################################################
        $message = "\nRegistering file into database\n";
        $this->spool($message, 'N', $upload_id, $notify_detailed);
        $fileID = &NeuroDB::MRI::register_db($minc_file);
        $message = "\nFileID: $fileID\n";
        $this->spool($message, 'N', $upload_id, $notify_detailed);

        ########################################################
        ### update mri_acquisition_dates table #################
        ########################################################
        my $acquisition_date = $tarchiveInfo->{'DateAcquired'}
            // $${minc_file}->getParameter('AcquisitionDate')
            // undef;
        $this->update_mri_acquisition_dates($sessionID, $acquisition_date);
    }
    return $acquisitionProtocolID;
}


=pod

=head3 dicom_to_minc($study_dir, $converter, $get_dicom_info, $exclude, $mail_user, $upload_id)

Converts a DICOM study into MINC files.

INPUTS:
  - $study_dir      : DICOM study directory to convert
  - $converter      : converter to be used
  - $get_dicom_info : get DICOM information setting from the C<Config> table
  - $exclude        : which files to exclude from the C<dcm2mnc> command
  - $mail_user      : mail of the user
  - $upload_id      : upload ID of the study

=cut

sub dicom_to_minc {

    my $this = shift;
    my ($study_dir, $converter,$get_dicom_info,
		$exclude,$mail_user, $upload_id) = @_;
    my ($d2m_cmd, $d2m_log, $exit_code, $excluded_regex);
    my $message = '';

    # create the excluded series description regex necessary to exclude the
    # series description specified in the Config Setting
    # excluded_series_description
    if ($exclude && ref($exclude) eq 'ARRAY') {
        $excluded_regex = join('|', map { quotemeta($_) } @$exclude);
    } elsif ($exclude) {
        $excluded_regex = $exclude;
    }
    $d2m_cmd = "find $study_dir -type f " .
               " | $get_dicom_info -studyuid -series -echo -image -file " .
               " -attvalue 0018 0024 -series_descr -stdin" .
               " | sort -n -k1 -k2 -k7 -k3 -k6 -k4 ";
    $d2m_cmd .= ' | grep -iv -P "\t(' . $excluded_regex . ')\s*$"' if ($excluded_regex);
    $d2m_cmd .= " | cut -f 5 | ";

    ############################################################
    #### use some other converter if specified in the config ###
    ############################################################
    if ($converter !~ /dcm2mnc/) {
        $d2m_cmd .= "$converter $this->{TmpDir}  -notape -compress -stdin";
    } else {
        $d2m_cmd .= "$converter -dname '' -stdin -clobber -usecoordinates $this->{TmpDir} ";
    }
    $d2m_log = `$d2m_cmd`;

    if ($? > 0) {
        $exit_code = $? >> 8;
        ########################################################
        # dicom_to_minc failed...  don't keep going, ########### 
        # just email. ##########################################
        ########################################################
        $message = "\nDicom to Minc conversion failed\n";
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);
        open MAIL, "| mail $mail_user";
        print MAIL "Subject: [URGENT Automated] uploadNeuroDB: ".
                   "dicom->minc failed\n";
        print MAIL "Exit code $exit_code received from:\n$d2m_cmd\n";
        close MAIL;
        croak("dicom_to_minc failure, exit code $exit_code");
   }

    $message = "\n" . $d2m_cmd . "\n";
    $this->{LOG}->print(
    "### Dicom to MINC:\n$d2m_log");
    $this->spool($message, 'N', $upload_id, $notify_detailed);
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
            'Mincinfo_wrapper -quiet -tab -file -attvalue %s %s',
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
    my $tarchivePath = NeuroDB::DBI::getConfigSetting(
                        $this->{dbhr},'tarchiveLibraryDir'
                        );
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

=head3 CreateMRICandidates($subjectIDsref, $gender, $tarchiveInfo, $User, $centerID, $upload_id)

Registers a new candidate in the C<candidate> table.

INPUTS:
  - $subjectIDsref: subject's ID information hash ref
  - $gender       : gender of the candidate
  - $tarchiveInfo : tarchive information hash ref
  - $User         : user that is running the pipeline
  - $centerID     : center ID
  - upload_id     : upload ID of the study

=cut

sub CreateMRICandidates {
    ############################################################
    ### Standardize gender (DICOM uses M/F, DB uses Male/Female)
    ############################################################
    my $this = shift;
    my $query = '';
    my ($subjectIDsref,$gender,$tarchiveInfo,$User,$centerID, $upload_id) = @_;
    my ($message);

    if ($tarchiveInfo->{'PatientGender'} eq 'F') {
            $gender = "Female";
    } elsif ($tarchiveInfo->{'PatientGender'} eq 'M') {
        $gender = "Male";
    }

    ################################################################
    ## Create non-existent candidate if the profile allows for #####
    ## Candidate creation ##########################################
    ################################################################
    if (!NeuroDB::MRI::subjectIDExists(
            $subjectIDsref->{'CandID'},
            $this->{dbhr}
        ) 
        && (NeuroDB::DBI::getConfigSetting($this->{dbhr},'createCandidates'))
    ) {
           chomp($User);
            unless ($subjectIDsref->{'CandID'}) {
                $subjectIDsref->{'CandID'} = 
                NeuroDB::MRI::createNewCandID($this->{dbhr});
            }
            $query = "INSERT INTO candidate ".
                     "(CandID, PSCID, DoB, Gender,CenterID, Date_active,".
                     " Date_registered, UserID,Entity_type) ".
                     "VALUES(" . 
                     ${$this->{'dbhr'}}->quote($subjectIDsref->{'CandID'}).",".
                     ${$this->{'dbhr'}}->quote($subjectIDsref->{'PSCID'}).",".
                     ${$this->{'dbhr'}}->quote($tarchiveInfo->{'PatientDoB'}) ."," .
                     ${$this->{'dbhr'}}->quote($gender).",". 
                     ${$this->{'dbhr'}}->quote($centerID). 
                     ", NOW(), NOW(), '$User', 'Human')";
            
            if ($this->{debug}) {
                print $query . "\n";
            }
            ${$this->{'dbhr'}}->do($query);
            $message = "\n==> CREATED NEW CANDIDATE :
            		$subjectIDsref->{'CandID'}";
            $this->{LOG}->print($message);
            $this->spool($message, 'N', $upload_id, $notify_detailed);
      } elsif ($subjectIDsref->{'CandID'}) {# if the candidate exists
            $message = "\n==> getSubjectIDs returned this CandID/DCCID : ".
               "$subjectIDsref->{'CandID'}\n";
	    $this->{LOG}->print($message);
            $this->spool($message, 'N', $upload_id, $notify_detailed);
      } else {
            $message = "\nERROR: The candidate could not be considered for ". 
                       "uploading, since s/he is not registered in your database.".
                       "\nThe dicom header PatientID is: ". 
                       $tarchiveInfo->{'PatientID'}. "\n ".
                       "The dicom header PatientName is: ". 
                       $tarchiveInfo->{'PatientName'}. "\n\n";
            $this->writeErrorLog(
                $message, $NeuroDB::ExitCodes::INSERT_FAILURE
            );
            $this->spool($message, 'Y', $upload_id, $notify_notsummary);
            exit $NeuroDB::ExitCodes::INSERT_FAILURE;
     }
}


=pod

=head3 setMRISession($subjectIDsref, $tarchiveInfo, $upload_id)

Sets the imaging session ID. This function will call
C<&NeuroDB::MRI::getSessionID> which in turn will either:
  - grep the session ID if visit for that candidate already exists, or
  - create a new session if visit label does not exist for that candidate yet

INPUTS:
  - $subjectIDsref: subject's ID information hashr ef
  - $tarchiveInfo : DICOM archive information hash ref
  - $upload_id    : upload ID of the study

RETURNS:
  - $sessionID      : session ID
  - $requiresStaging: whether the new session requires staging

=cut

sub setMRISession {
    my $this = shift;
    my $query = '';
    my ($subjectIDsref, $tarchiveInfo, $upload_id) = @_;
    my $message = '';

    ############################################################
    # This will actually create a visit count if it is not ##### 
    # provided through the IDs in the dicom header The count ### 
    # starts with 1 if there is none. ##########################
    ############################################################
    if (!defined($subjectIDsref->{'visitLabel'})) {
        $subjectIDsref->{'visitLabel'} =
        lookupNextVisitLabel(
            $subjectIDsref->{'CandID'}, 
            $this->{dbhr}
        );
    }
    ############################################################
    ################## get session ID ##########################
    ############################################################
    $message = "\n==> Getting session ID\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    my ($sessionID, $requiresStaging) =
        NeuroDB::MRI::getSessionID(
            $subjectIDsref, 
            $tarchiveInfo->{'DateAcquired'}, 
            $this->{dbhr}, 
            $subjectIDsref->{'subprojectID'}
        );
    $message = "\nSessionID: $sessionID\n";    
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);
    # Staging: $requiresStaging\n";
    ############################################################
    # Make sure MRI Scan Done is set to yes, because now ####### 
    # there is data. ###########################################
    ############################################################
    if ($sessionID) {
        $query = "UPDATE session SET Scan_done='Y' WHERE ID=$sessionID";
        if ($this->{debug}) {
            print $query . "\n";
        }
        ${$this->{'dbhr'}}->do($query);
    }
    return ($sessionID, $requiresStaging);
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

=head3 which_directory($subjectIDsref, $data_dir)

Determines where the MINC files to be registered into the database will go.

INPUTS:
   - $subjectIDsref: subject's ID information hashref
   - $data_dir     : data directory (e.g. C</data/$PROJECT/data>)

RETURNS: the final directory in which the registered MINC files will go
(typically C</data/$PROJECT/data/assembly/CandID/visit/mri/>)

=cut

sub which_directory {
    my $this = shift;
    my ($subjectIDsref,$data_dir) = @_;
    my %subjectIDs = %$subjectIDsref;
    my $dir = $data_dir;
    $dir = "$dir/assembly/$subjectIDs{'CandID'}/$subjectIDs{'visitLabel'}/mri";
    $dir =~ s/ //;
    return $dir;
}


=pod

=head3 validateCandidate($subjectIDsref)

Check that the candidate's information derived from the patient name field of
the DICOM files is valid (C<CandID> and C<PSCID> of the candidate should
correspond to the same subject in the database).

INPUT: subject's ID information hash ref

RETURNS: the candidate mismatch error, or undef if the candidate is validated
or a phantom

=cut

sub validateCandidate {
    my $this = shift;
    my ($subjectIDsref)= @_;
    my $CandMismatchError = undef;
    
    #################################################################
    ## Check if CandID exists
    #################################################################
    my $query = "SELECT CandID, PSCID FROM candidate WHERE CandID=?";
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($subjectIDsref->{'CandID'});
    print "candidate id " . $subjectIDsref->{'CandID'} . "\n" 
	if ($this->{verbose});
    if ($sth->rows == 0) {
        print LOG  "\n\n=> Could not find candidate with CandID =".
                   " $subjectIDsref->{'CandID'} in database\n";
        $CandMismatchError = 'CandID does not exist';
        return $CandMismatchError;
    }
    
    #################################################################
    ### Check if PSCID exists and that PSCID and CandID of the scan
    # refers to the same candidate
    #################################################################
    $query = "SELECT CandID, PSCID FROM candidate WHERE PSCID=?";
    $sth =  ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($subjectIDsref->{'PSCID'});
    if ($sth->rows == 0) {
        print LOG "\n=> No PSCID\n";
        $CandMismatchError= 'PSCID does not exist';
        return $CandMismatchError;
    } else {
        # Check that the PSCID and CandID refers to the same candidate
        my $rowref = $sth->fetchrow_hashref;
        unless ($rowref->{'CandID'} == $subjectIDsref->{'CandID'}) {
            $CandMismatchError = 'PSCID and CandID of the image mismatch\n';
            print LOG "\n=> $CandMismatchError";
            return $CandMismatchError;
        }
    }

    ############################################################
    ################ No Checking if the subject is Phantom #####
    ############################################################
    if ($subjectIDsref->{'isPhantom'}) {
        # CandID/PSCID errors don't apply to phantoms, so we don't
        # want to trigger
        # the check which aborts the insertion
        $CandMismatchError = undef;
        return $CandMismatchError;
    }

    ############################################################
    ################ Check if visitLabel exists ################
    ############################################################

    $query = "SELECT Visit_label FROM Visit_Windows WHERE BINARY Visit_label=?";
    $sth =  ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($subjectIDsref->{'visitLabel'});
    if (($sth->rows == 0) && (!$subjectIDsref->{'createVisitLabel'})) {
        print LOG "\n=> No Visit label\n";
        $CandMismatchError= 'Visit label does not exist';
        return $CandMismatchError;
    } elsif (($sth->rows == 0) && ($subjectIDsref->{'createVisitLabel'})) {
        print LOG "\n=> Will create visit label $subjectIDsref->{'visitLabel'}\n";
    } 

   return $CandMismatchError;
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

    my $data_dir   = NeuroDB::DBI::getConfigSetting($this->{dbhr},'dataDirBasepath');
    my $modalities = NeuroDB::DBI::getConfigSetting(
        $this->{dbhr}, 'compute_snr_modalities'
    );

    (my $query = <<QUERY) =~ s/\n//gm;
  SELECT    FileID, File, Scan_type
  FROM      files f
  JOIN      mri_scan_type mst ON (mst.ID=f.AcquisitionProtocolID)
  WHERE     f.TarchiveSource=?
QUERY
    print $query . "\n" if ($this->{debug});
    my $minc_file_arr = ${$this->{'dbhr'}}->prepare($query);
    $minc_file_arr->execute($tarchiveID);

    while (my $row = $minc_file_arr->fetchrow_hashref()) {
        my $filename     = $row->{'File'};
        my $fileID       = $row->{'FileID'};
        my $fileScanType = $row->{'Scan_type'};
        my $base         = basename($filename);
        my $fullpath     = "$data_dir/$filename";
        my $message;
        if ( grep($_ eq $fileScanType, @$modalities) ) {
            my $cmd = "noise_estimate --snr $fullpath";
            my $SNR = `$cmd`;
            $SNR =~ s/\n//g;
            print "$cmd \nSNR is: $SNR \n" if ($this->{verbose});
            my $file = NeuroDB::File->new($this->{dbhr});
            $file->loadFile($fileID);
            my $SNR_old = $file->getParameter('SNR');
            if ($SNR ne '') {
                $file->setParameter('SNR', $SNR);
                if (($SNR_old ne '') && ($SNR_old ne $SNR)) {
                    $message = "The SNR value was updated from $SNR_old to $SNR.\n";
                    $this->{LOG}->print($message);
                    $this->spool($message, 'N', $upload_id, $notify_detailed);
                }
            }
        } else {
            $message = "The SNR can not be computed for $base as the imaging "
                       . "modality is not supported by the SNR computation. The "
                       . "supported modalities for your projects are "
                       . join(', ', @$modalities) . ".\n";
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

    my $queryAcqProt = "SELECT DISTINCT f.AcquisitionProtocolID ".
                        "FROM files f ".
                        "WHERE f.TarchiveSource=?";   

    if ($this->{debug}) {
        print $queryAcqProt . "\n";
    }

    my $acqArr = ${$this->{'dbhr'}}->prepare($queryAcqProt);
    $acqArr->execute($tarchiveID);
    # For each of the files having this AcquisitionProtocolID
    # load the file object to get the series_number  
    while (my $rowAcqProt = $acqArr->fetchrow_hashref()) {
        $acqProtID = $rowAcqProt->{'AcquisitionProtocolID'};
        my $queryDataArr = "SELECT f.FileID, f.AcqOrderPerModality ".
                            "FROM files f ".
                            "WHERE f.TarchiveSource=? AND f.AcquisitionProtocolID=?";

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

=head3 isValidMRIProtocol()

Ensures no column in the C<mri_protocol> nor the C<mri_protocol_checks> 
tables has comma-separated values.

RETURNS: 1 on success, 0 on failure

=cut

sub isValidMRIProtocol  {
    my $this = shift;

    my $query = "SELECT COUNT(*) FROM mri_protocol 
                WHERE TR_range LIKE '%,%'
                OR TE_range LIKE '%,%'
                OR TI_range LIKE '%,%'
                OR slice_thickness_range LIKE '%,%'
                OR xspace_range LIKE '%,%'
                OR yspace_range LIKE '%,%'
                OR zspace_range LIKE '%,%'
                OR xstep_range LIKE '%,%'
                OR ystep_range LIKE '%,%'
                OR zstep_range LIKE '%,%'
                OR time_range LIKE '%,%'";

    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();
    my $count_mri_protocol = $sth->fetchrow_array;

    $query = "SELECT COUNT(*) FROM mri_protocol_checks 
                WHERE ValidRange LIKE '%,%'";

    $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();
    my $count_mri_protocol_checks = $sth->fetchrow_array;

    if ( $count_mri_protocol > 0 || $count_mri_protocol_checks > 0) {
        return 0;  
    } else {
        return 1;
    }
}

=pod

=head3 is_file_unique($file, $upload_id)

Queries the C<files> and C<parameter_file> tables to make sure that no imaging
datasets with the same C<SeriesUID> and C<EchoTime> or the same C<MD5sum> hash
can be found in the database already. If there is a match, it will return a
message with the information about why the file is not unique. If there is no
match, then it will return undef.

INPUTS:
  - $file     : the file object from the C<NeuroDB::File> package
  - $upload_id: the C<UploadID> associated to the file

RETURNS: a message with the reason why the file is not unique or undef

=cut

sub is_file_unique {

    my $this = shift;
    my ($file, $upload_id) = @_;

    my $seriesUID = $file->getParameter( 'series_instance_uid' );
    my $echo_time = $file->getParameter( 'echo_time'           );

    # check that no files are already in the files table with the same SeriesUID
    # and EchoTime
    my $query     = "SELECT File FROM files WHERE SeriesUID=? AND EchoTime=?";
    my $sth       = ${$this->{'dbhr'}}->prepare( $query );
    $sth->execute( $seriesUID, $echo_time );
    my $results = $sth->fetchrow_array;
    my $message;
    if (defined $results) {
        $message = "\n--> ERROR: there is already a file registered in the files "
                   . "table with SeriesUID='$seriesUID' and EchoTime='$echo_time'.\n"
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

Remove the function isValidMRIProtocol() once the database schema is configured 
to prevent users from entering non-conform entries in the C<mri_protocol> table

Fix comments written as #fixme in the code

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

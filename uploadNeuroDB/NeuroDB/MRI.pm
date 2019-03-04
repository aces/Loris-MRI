package NeuroDB::MRI;

=pod

=head1 NAME

NeuroDB::MRI -- A set of utility functions for performing common tasks
relating to MRI data (particularly with regards to registering MRI
files into the LORIS system)

=head1 SYNOPSIS

 use NeuroDB::File;
 use NeuroDB::MRI;
 use NeuroDB::DBI;

 my $dbh = NeuroDB::DBI::connect_to_db();

 my $file = NeuroDB::File->new(\$dbh);

 $file->loadFileFromDisk('/path/to/some/file');
 $file->setFileData('CoordinateSpace', 'nonlinear');
 $file->setParameter('patient_name', 'Larry Wall');

 my $parameterTypeID = $file->getParameterTypeID('patient_name');
 my $parameterTypeCategoryID = $file->getParameterTypeCategoryID('MRI Header');

=head1 DESCRIPTION

Really a mishmash of utility functions, primarily used by C<process_uploads> and
all of its children.

=head2 Methods

=cut


use Exporter();
use Math::Round;
use Time::JulianDay;
use File::Temp qw(tempdir);
use File::Basename;
use Data::Dumper;
use Carp;
use Time::Local;
use FindBin;
use DICOM::DICOM;

$VERSION = 0.2;
@ISA = qw(Exporter);

# Number of decimals considered when testing if two floats are equal
$FLOAT_EQUALS_NB_DECIMALS = 4;

@EXPORT = qw();
@EXPORT_OK = qw(identify_scan in_range get_headers get_info get_ids get_objective identify_scan_db scan_type_text_to_id scan_type_id_to_text register_db get_header_hash get_scanner_id get_psc compute_hash is_unique_hash make_pics select_volume);

=pod

=head3 getSubjectIDs($patientName, $scannerID, $dbhr)

Determines the candidate ID and visit label for the subject based on patient
name and (for calibration data) scanner ID.

INPUTS:
  - $patientName: patient name
  - $scannerID  : scanner ID
  - $dbhr       : database handle reference

RETURNS: a reference to a hash containing elements including C<CandID>,
C<visitLabel> and C<visitNo>, or, in the case of failure, C<undef>

=cut

sub getSubjectIDs {
    my ($patientName, $scannerID, $dbhr) = @_;
    my %subjectID;
# calibration data (PHANTOM_site_date | LIVING_PHANTOM_site_date | *test*)
    if ($patientName =~ /PHA/i or $patientName =~ /TEST/i) {
	$subjectID{'CandID'} = my_trim(getScannerCandID($scannerID, $dbhr));
	$subjectID{'visitLabel'} = my_trim($patientName);
# subject data
# old versions of this
# qnts /([A-Z-]{3,4}\s+\d+)_(\d+)_([^_ ]+)/) or nihpd =~ /(\w{3}\d+)_(\d+)_([^_ ]+)/)
    } elsif ($patientName =~ /([^_]+)_(\d+)_([^_ ]+)/) {
	$subjectID{'PSCID'} = my_trim($1);
	$subjectID{'CandID'} = my_trim($2);
	$subjectID{'visitLabel'} = my_trim($3);
	if(!subjectIDIsValid($subjectID{'CandID'}, $subjectID{'PSCID'}, $subjectID{'visitLabel'}, $dbhr)) {
	    return undef;
	}
    }
    my $sth = $${dbhr}->prepare("SELECT VisitNo FROM session WHERE CandID='$subjectID{'CandID'}' AND Visit_label='$subjectID{'visitLabel'}' AND Active='Y'");
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $subjectID{'visitNo'} = $row->{'VisitNo'};

    return \%subjectID;
}

=pod

=head3 subjectIDIsValid($CandID, $PSCID, $visit_label, $dbhr, $create_visit_label)

Verifies that the subject IDs match.

INPUTS:
  - $candID            : candidate's C<CandID>
  - $pscid             : candidate's C<PSCID>
  - $visit_label       : visit label
  - $dbhr              : the database handle reference
  - $create_visit_label: boolean, if true, will create the visit label

RETURNS: 1 if the ID pair matches, 0 otherwise

=cut

sub subjectIDIsValid {
    my ($candID, $pscid, $visit_label, $dbhr, $create_visit_label) = @_;
    my $query = "SELECT COUNT(*) AS isValid FROM candidate WHERE CandID=".$${dbhr}->quote($candID)." AND PSCID=".$${dbhr}->quote($pscid);
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();

    my $rowhr = $sth->fetchrow_hashref();

    # Check that visit label exists in the database if don't want to create visit labels via imaging pipeline
    if (($rowhr->{'isValid'} == 1) && (!$create_visit_label)) {
        $query = "SELECT COUNT(*) AS isValid FROM Visit_Windows WHERE BINARY Visit_label=".$${dbhr}->quote($visit_label);
        $sth = $${dbhr}->prepare($query);
        $sth->execute();

        $rowhr = $sth->fetchrow_hashref();
    }
    return $rowhr->{'isValid'} == 1;
}

=pod

=head3 subjectIDExists($CandID, $dbhr)

Verifies that the subject ID (C<CandID>) exists.

INPUTS:
  - $candID: candidate's C<CandID>
  - $dbhr  : the database handle reference

RETURNS: 1 if the ID exists, 0 otherwise

=cut

sub subjectIDExists {
    my ($candID, $dbhr) = @_;

    my $query = "SELECT COUNT(*) AS idExists FROM candidate WHERE CandID=".$${dbhr}->quote($candID);
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();

    my $rowhr = $sth->fetchrow_hashref();
    return $rowhr->{'idExists'} > 0;
}

=pod

=head3 getScannerCandID($scannerID, $dbhr)

Retrieves the candidate (C<CandID>) for the given scanner.

INPUTS: the scanner ID and the database handle reference

RETURNS: the C<CandID> or (if none exists) undef

=cut

sub getScannerCandID {
    my ($scannerID, $dbhr) = @_;
    my $candID;

    my $query = "SELECT CandID FROM mri_scanner WHERE ID=$scannerID";
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();

    if($sth->rows > 0) {
	my $rowref = $sth->fetchrow_hashref();
	return $rowref->{'CandID'};
    } else {
	return undef;
    }
}

=pod

=head3 getSessionID($subjectIDref, $studyDate, $dbhr, $objective, $noStagingCheck)

Gets (or creates) the session ID, given C<CandID> and visit label (contained
inside the hash ref C<$subjectIDref>).  Unless C<$noStagingCheck> is true, it
also determines whether staging is required using the C<$studyDate>
(formatted YYYYMMDD) to determine whether staging is required based on a
simple algorithm:

=over 3

- If there exists a session with the same visit label, then that is
   the session ID to use.  If any dates (either existing MRI data or
   simply a date of visit) exist associated with that session, then
   if they are outside of some (arbitrary) time window, staging is
   required.  If no dates exist, no staging is required.

- If no sessions exist, then if there is any other date associated
   with another session of the same subject within a time window,
   staging is required.

- Otherwise, staging is not required.

=back

INPUTS:
  - $subjectIDref  : hash reference of subject IDs
  - $studyDate     : study date
  - $dbhr          : database handle reference
  - $objective     : the objective of the study
  - $noStagingCheck: a no staging check flag

RETURNS: a list of two items, (C<sessionID>, C<requiresStaging>)

=cut

sub getSessionID {
    my ($subjectIDref, $studyDate, $dbhr, $objective, $noStagingCheck) = @_;
    my ($sessionID, $requiresStaging, $studyDateJD);
    my ($query, $sth);
    my $dbh = $$dbhr;

# find a matching timepoint
    $query = "SELECT ID, Date_visit, Visit FROM session WHERE CandID=$subjectIDref->{'CandID'} AND LOWER(Visit_label)=LOWER(".$dbh->quote($subjectIDref->{'visitLabel'}).") AND Active='Y'";
    $sth = $dbh->prepare($query);
    $sth->execute();

##### if it finds an existing session it does this:
    if($sth->rows > 0) {
	$requiresStaging = 1 unless $noStagingCheck;
	my $timepoint = $sth->fetchrow_hashref();
	$sessionID = $timepoint->{'ID'};
	$sth->finish();

	# check dates, to determine if staging is required
	# check date of visit, if available
	if($timepoint->{'Date_visit'}) {
	    my @visitDate = split(/-/, $timepoint->{'Date_visit'});
	    my $timepointJD = julian_day($visitDate[0], $visitDate[1], $visitDate[2]);
	}
	if(defined($studyDate) && $studyDate =~ /^(\d{4})(\d{2})(\d{2})/) {
	    # compute the julian date of the study
	    $studyDateJD = julian_day($1, $2, $3);
	} else {
	    # no study date, so no staging
	    $requiresStaging = 0;
	}
	# staging not required if the study date matches the timepoint date of visit
	if(defined($studyDateJD) and defined($timepointJD) and $studyDateJD == $timepointJD) {
	    $requiresStaging = 0;
	}

	# check dates of other files
	if(defined($studyDateJD) and $requiresStaging == 1) {
	    # get the set of files
	    $query = "SELECT FileID FROM files WHERE SessionID=$sessionID AND FileType='mnc' AND OutputType='native'";
	    $sth = $dbh->prepare($query);
	    $sth->execute();

	    if($sth->rows > 0) {
		my @files = ();
		while(my $filehr = $sth->fetchrow_hashref()) { push @files, $filehr->{'FileID'}; }
		$sth->finish();

		# run the check
		$requiresStaging = checkMRIStudyDates($studyDateJD, $dbhr, @files);
	    }
	}

#####  if there is no existing session, which always happens if you create candidates based on incoming data
    } else {
	$requiresStaging = 0;

	# determine the visit number and centerID for the next session
        my $newVisitNo = 0;
        my $centerID = 0;

        if($subjectIDref->{'visitLabel'} =~ /PHA/i or $subjectIDref->{'visitLabel'} =~ /TEST/i) {
	    # calibration data (PHANTOM_site_date | LIVING_PHANTOM_site_date | *test*)
            my @pscInfo = getPSC($subjectIDref->{'visitLabel'}, $dbhr);
            $centerID = $pscInfo[1];
        }
	# fixme ask Jon ... is this still useful?
    # determine the centerID and new visit number (which is now deprecated) if getPSC() failed.
	if($centerID == 0) {
            $query = "SELECT IFNULL(MAX(VisitNo), 0)+1 AS newVisitNo, CenterID FROM session WHERE CandID=".$dbh->quote($subjectIDref->{'CandID'})." GROUP BY CandID, CenterID";
            $sth = $dbh->prepare($query);
            $sth->execute();
            if($sth->rows > 0) {
                my $rowref = $sth->fetchrow_hashref();
                $newVisitNo = $rowref->{'newVisitNo'};
                $centerID = $rowref->{'CenterID'};
                # fixme add some debug messages if this is to be kept
                print "Set newVisitNo = $newVisitNo and centerID = $centerID\n";
            } else {
                $query = "SELECT CenterID FROM candidate WHERE CandID=".$dbh->quote($subjectIDref->{'CandID'});
                $sth = $dbh->prepare($query);
                $sth->execute();
                if($sth->rows > 0) {
                    my $rowref = $sth->fetchrow_hashref();
                    $centerID = $rowref->{'CenterID'};
                    print "Set centerID = $centerID\n";
                } else {
                    $centerID = 0;
                    print "No centerID\n";
                }
            }
        }

        $newVisitNo = 1 unless $newVisitNo;
        $centerID = 0 unless $centerID;

#### insert the new session setting Current_stage to 'Not started' because that column is important to the behavioural data entry gui.
	$query = "INSERT INTO session SET CandID=".$dbh->quote($subjectIDref->{'CandID'}).", Visit_label=".$dbh->quote($subjectIDref->{'visitLabel'}).", CenterID=$centerID, VisitNo=$newVisitNo, Current_stage='Not Started', Scan_done='Y', Submitted='N', SubprojectID=".$dbh->quote($objective);
 	$dbh->do($query); # execute query
	$sessionID = $dbh->{'mysql_insertid'}; # retain id of inserted row
	$subjectIDref->{'visitNo'} = $newVisitNo; # add visit number to subjectIDref

	# check dates of other files
	if(defined($studyDateJD) and !$noStagingCheck) {
	    # get the set of sessions for the subject
	    $query = "SELECT ID FROM session WHERE CandID=$subjectIDref->{'CandID'} AND Active='Y'";
	    $sth = $dbh->prepare($query);
	    $sth->execute();

	    if($sth->rows > 0) {
		my @sessionIDs = ();
		while(my $session = $sth->fetchrow_array()) { push @sessionIDs, $session[0]; }
		$sth->finish();

		# get the set of files
		$query = "SELECT FileID FROM files WHERE SessionID IN (".join(',', @sessionIDs)." AND FileType='mnc' AND OutputType='native'";
		$sth = $dbh->prepare($query);
		$sth->execute();

		if($sth->rows > 0) {
		    my @files = ();
		    while(my $filearray = $sth->fetchrow_array()) { push @files, $filearray[0]; }

		    $sth->finish();

		    # run the check - note it's backwards (!) because this
		    # time we're looking for mris in other studies which
		    # are confounding rather than mris in this study which
		    # are supporting
		    $requiresStaging = !checkMRIStudyDates($studyDateJD, $dbhr, @files);
		} # end if sth->rows (files)
	    } # end if sth->rows (sessionIDs)
	} # end if defined studyDateJD
    }

    return ($sessionID, $requiresStaging);
}

=pod

=head3 checkMRIStudyDates($studyDateJD, $dbhr, @fileIDs)

This method tries to figure out if there may have been labelling problems which
would put the files in a staging area that does not actually exist.

INPUTS:
  - $studyDateJD: study date
  - $dbhr       : database handle reference
  - @fileIDs    : array of C<fileIDs> to check the study date

RETURNS: 1 if the file requires staging, 0 otherwise

=cut

sub checkMRIStudyDates {
    my ($studyDateJD, $dbhr, @fileIDs) = @_;

    if(scalar(@fileIDs) == 0) {
	carp "No fileIDs passed in to checkMRIStudyDates\n";
	return 0;
    }

    my $requiresStaging = 1;
    my $file = NeuroDB::File->new($dbhr);
    my $studyDateID = $file->getParameterTypeID('study_date');

    # check the other files
    my $query = "SELECT DISTINCT Value FROM parameter_file WHERE ParameterTypeID=$studyDateID AND FileID IN (".join(',', @fileIDs).")";
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();

    if($sth->rows > 0) {
      LOOP_FILES: {
	  while(my $row = $sth->fetchrow_hashref()) {
	      if($row->{'Value'} =~ /^(\d{4})(\d{2})(\d{2})/) {
		  my $eventJD = julian_day($1, $2, $3);
		  if($eventJD == $studyDateJD) {
		      $requiresStaging = 0;
		      last LOOP_FILES;
		  }
	      }
	  } # end while
      } # end LOOP_FILES
    } # end if $sth->rows (parameters)

    return $requiresStaging;
}

=pod

=head3 getObjective($subjectIDsref, $dbhr)

Attempts to determine the C<SubprojectID> of a timepoint given the subject IDs
hash ref C<$subjectIDsref> and a database handle reference C<$dbhr>

INPUTS:
  - $subjectIDsref: subjectIDs hashref
  - $dbhr         : database handle reference

RETURNS: the determined objective, or 0

=cut

sub getObjective
{
    my ($subjectIDsref, $dbhr) = @_;
    my @results = ();
    my $objective = 0;
    my %subjectIDs = %$subjectIDsref;
    if($subjectIDs{'visitLabel'} =~ /PHA/i or $subjectIDs{'visitLabel'} =~ /TEST/i) {
	return 0;
    }

    my $query = "SELECT SubprojectID FROM session WHERE CandID='$subjectIDs{'CandID'}' AND Visit_label='$subjectIDs{'visitLabel'}' AND Active='Y' ORDER BY ID DESC LIMIT 1";
    my $sth = $${dbhr}->prepare($query) or die "Can't prepare $query: ".$${dbhr}->errstr."\n";

    $sth->execute();

    if($sth->rows > 0) {
        @results = $sth->fetchrow_array();
    }

    $objective = $results[0] if $results[0];

    unless($objective>0) {
        # there probably isn't a valid row for this visit...
        $query = "SELECT SubprojectID FROM session WHERE CandID='$subjectIDs{'CandID'}' AND Active='Y' ORDER BY ID DESC LIMIT 1";
        $sth = $${dbhr}->prepare($query);
        $sth->execute();

        @results = $sth->fetchrow_array();

        $objective = $results[0] if $results[0];
    }
    return $objective;

}


=pod

=head3 identify_scan_db($center_name, $objective, $fileref, $dbhr)

Determines the type of the scan described by MINC headers based on
C<mri_protocol> table in the database.

INPUTS:
  - $center_name: center's name
  - $objective  : objective of the study
  - $fileref    : file hash ref
  - $dbhr       : database handle reference

RETURNS: textual name of scan type from the C<mri_scan_type> table

=cut

sub identify_scan_db {

    my  ($psc, $subjectref, $tarchiveInfoRef, $fileref, $dbhr,$minc_location
    ) = @_;

    my $candid = ${subjectref}->{'CandID'};
    my $pscid = ${subjectref}->{'PSCID'};
    my $visit = ${subjectref}->{'visitLabel'};
    my $tarchiveID = $tarchiveInfoRef->{'TarchiveID'};
    my $objective = ${subjectref}->{'subprojectID'};

    # get parameters from minc header
    my $patient_name =  ${fileref}->getParameter('patient_name');

    my $xstep = ${fileref}->getParameter('xstep');
    my $ystep = ${fileref}->getParameter('ystep');
    my $zstep = ${fileref}->getParameter('zstep');

    my $xspace = ${fileref}->getParameter('xspace');
    my $yspace = ${fileref}->getParameter('yspace');
    my $zspace = ${fileref}->getParameter('zspace');
    my $slice_thickness = ${fileref}->getParameter('slice_thickness');
    my $seriesUID = ${fileref}->getParameter('series_instance_uid');
    my $series_description = ${fileref}->getParameter('series_description');

    # get parameters specific to MRIs
    my ($tr, $te, $ti, $time);
    if ($fileref->{parameters}{modality} eq "MR") {
        $tr = ${fileref}->getParameter('repetition_time');
        $te = ${fileref}->getParameter('echo_time');
        $ti = ${fileref}->getParameter('inversion_time');
        if (defined($tr)) {  $tr = &Math::Round::nearest(0.01, $tr*1000);  }
        if (defined($te)) {  $te = &Math::Round::nearest(0.01, $te*1000);  }
        if (defined($ti)) {  $ti = &Math::Round::nearest(0.01, $ti*1000);  }
        $time = ${fileref}->getParameter('time');
    } elsif ($fileref->{parameters}{modality} eq "PT") {
        # Place to add stuff specific to PET images
    }
    if(0) {
        if ($fileref->{parameters}{modality} eq "MR") {
            print "\ntr:\t$tr\nte:\t$te\nti:\t$ti\nst:\t$slice_thickness\n";
        }
        print "time;\t$time\n";
        print "xspace:\t$xspace\nyspace:\t$yspace\nzspace:\t$zspace\n";
        print "xstep:\t$xstep\nystep:\t$ystep\nzstep:\t$zstep\n";
    }

    # compute n_slices from DIMnele's
    my $n_slices = 0;

    # get ScannerID from DB
    my $manufacturer = ${fileref}->getParameter('manufacturer');
    my $model = ${fileref}->getParameter('manufacturer_model_name');
    my $serial_number = ${fileref}->getParameter('device_serial_number');
    my $software = ${fileref}->getParameter('software_versions');

    my $query = "SELECT ID FROM mri_scanner WHERE Manufacturer='$manufacturer' AND Model='$model' AND Serial_number='$serial_number' AND Software='$software'";


    my $sth = $${dbhr}->prepare($query);
    $sth->execute();

    # default ScannerID to 0 if we have no better clue.
    my $ScannerID = 0;
    if($sth->rows>0) {
        my @results = $sth->fetchrow_array();
        $ScannerID=$results[0];
    }


    # get the list of protocols for a site their scanner and subproject
    $query = "SELECT Scan_type, ScannerID, Center_name, TR_range, TE_range, TI_range, slice_thickness_range, xspace_range, yspace_range, zspace_range,
              xstep_range, ystep_range, zstep_range, time_range, series_description_regex
              FROM mri_protocol
              WHERE
             (Center_name='$psc' AND ScannerID='$ScannerID')
              OR ((Center_name='ZZZZ' OR Center_name='AAAA') AND ScannerID='0')
              ORDER BY Center_name ASC, ScannerID DESC";

    $sth = $${dbhr}->prepare($query);
    $sth->execute();
    return 'unknown' unless $sth->rows>0;

    # check against all possible scan types
    my $rowref;

    while($rowref = $sth->fetchrow_hashref()) {
        my $sd_regex = $rowref->{'series_description_regex'};
        if(0) {
            print "\tChecking ".&scan_type_id_to_text($rowref->{'Scan_type'}, $dbhr)." ($rowref->{'Scan_type'}) ($series_description =~ $sd_regex)\n";
            print "\t";
            if($sd_regex && ($series_description =~ /$sd_regex/i)) {print "series_description\t";}
            print &in_range($tr, $rowref->{'TR_range'}) ? "TR\t" : '';
            print &in_range($te, $rowref->{'TE_range'}) ? "TE\t" : '';
            print &in_range($ti, $rowref->{'TI_range'}) ? "TI\t" : '';
            print &in_range($xspace, $rowref->{'xspace_range'}) ? "xspace\t" : '';
            print &in_range($yspace, $rowref->{'yspace_range'}) ? "yspace\t" : '';
            print &in_range($zspace, $rowref->{'zspace_range'}) ? "zspace\t" : '';
            print &in_range($slice_thickness, $rowref->{'slice_thickness_range'}) ? "ST\t" : '';
            print &in_range($xstep, $rowref->{'xstep_range'}) ? "xstep\t" : '';
            print &in_range($ystep, $rowref->{'ystep_range'}) ? "ystep\t" : '';
            print &in_range($zstep, $rowref->{'zstep_range'}) ? "zstep\t" : '';
            print &in_range($time, $rowref->{'time_range'}) ? "time\t" : '';
            print "\n";
        }

	if ($sd_regex) {
            if ($series_description =~ /$sd_regex/i) {
                return &scan_type_id_to_text($rowref->{'Scan_type'}, $dbhr);
            }
	}
	else {
         	if ((!$rowref->{'TR_range'} || &in_range($tr, $rowref->{'TR_range'}))
                && (!$rowref->{'TE_range'} || &in_range($te, $rowref->{'TE_range'}))
                && (!$rowref->{'TI_range'} || &in_range($ti, $rowref->{'TI_range'}))
                && (!$rowref->{'slice_thickness_range'} || &in_range($slice_thickness, $rowref->{'slice_thickness_range'}))

                && (!$rowref->{'xspace_range'} || &in_range($xspace, $rowref->{'xspace_range'}))
                && (!$rowref->{'yspace_range'} || &in_range($yspace, $rowref->{'yspace_range'}))
                && (!$rowref->{'zspace_range'} || &in_range($zspace, $rowref->{'zspace_range'}))

                && (!$rowref->{'xstep_range'} || &in_range($xstep, $rowref->{'xstep_range'}))
                && (!$rowref->{'ystep_range'} || &in_range($ystep, $rowref->{'ystep_range'}))
                && (!$rowref->{'zstep_range'} || &in_range($zstep, $rowref->{'zstep_range'}))
                && (!$rowref->{'time_range'} || &in_range($time, $rowref->{'time_range'}))) {
                    return &scan_type_id_to_text($rowref->{'Scan_type'}, $dbhr);
            }
        }
    }

    # if we got here, we're really clueless...
    insert_violated_scans(
        $dbhr,   $series_description, $minc_location,   $patient_name,
        $candid, $pscid,              $tr,              $te,
        $ti,     $slice_thickness,    $xstep,           $ystep,
        $zstep,  $xspace,             $yspace,          $zspace,
        $time,   $seriesUID,          $tarchiveID
    );

    return 'unknown';
}

=pod

=head3 insert_violated_scans($dbhr, $series_desc, $minc_location, $patient_name, $candid, $pscid, $visit, $tr, $te, $ti, $slice_thickness, $xstep, $ystep, $zstep, $xspace, $yspace, $zspace, $time, $seriesUID)

Inserts scans that do not correspond to any of the defined protocol from the
C<mri_protocol> table into the C<mri_protocol_violated_scans> table of the
database.

INPUTS:
  - $dbhr           : database handle reference
  - $series_desc    : series description of the scan
  - $minc_location  : location of the MINC file
  - $patient_name   : patient name of the scan
  - $candid         : candidate's C<CandID>
  - $pscid          : candidate's C<PSCID>
  - $visit          : visit of the scan
  - $tr             : repetition time of the scan
  - $te             : echo time of the scan
  - $ti             : inversion time of the scan
  - $slice_thickness: slice thickness of the image
  - $xstep          : C<x-step> of the image
  - $ystep          : C<y-step> of the image
  - $zstep          : C<z-step> of the image
  - $xspace         : C<x-space> of the image
  - $yspace         : C<y-space> of the image
  - $zspace         : C<z-space> of the image
  - $time           : time dimension of the scan
  - $seriesUID      : C<SeriesUID> of the scan

=cut

sub insert_violated_scans {

    my ($dbhr,   $series_description, $minc_location, $patient_name,
        $candid, $pscid,              $tr,            $te,
        $ti,     $slice_thickness,    $xstep,         $ystep,
        $zstep,  $xspace,             $yspace,        $zspace,
        $time,   $seriesUID,          $tarchiveID) = @_;

    # determine the future relative path when the file will be moved to
    # data_dir/trashbin at the end of the script's execution
    my $file_rel_path = get_trashbin_file_rel_path($minc_location);

    (my $query = <<QUERY) =~ s/\n//gm;
  INSERT INTO mri_protocol_violated_scans (
    CandID,             PSCID,         TarchiveID,            time_run,
    series_description, minc_location, PatientName,           TR_range,
    TE_range,           TI_range,      slice_thickness_range, xspace_range,
    yspace_range,       zspace_range,  xstep_range,           ystep_range,
    zstep_range,        time_range,    SeriesUID
  ) VALUES (
    ?, ?, ?, now(),
    ?, ?, ?, ?,
    ?, ?, ?, ?,
    ?, ?, ?, ?,
    ?, ?, ?
  )
QUERY

    my $sth = $${dbhr}->prepare($query);
    my $success = $sth->execute(
        $candid,        $pscid,           $tarchiveID, $series_description,
        $file_rel_path, $patient_name,    $tr,         $te,
        $ti,            $slice_thickness, $xspace,     $yspace,
        $zspace,        $xstep,           $ystep,      $zstep,
        $time,          $seriesUID
    );

}


=pod

=head3 debug_inrange($val, $range)

Will evaluate whether the scalar C<$value> is in the specified C<$range>.

INPUTS:
  - $val  : scalar value to evaluate
  - $range: scalar range string

RETURNS: 1 if in range, 0 if not in range

=cut

sub debug_inrange {
    my $val = shift;
    my $range = shift;

    if(&in_range($val, $range)) {
        print "$val IN $range\n";
        return 1;
    } else {
        print "$val NOT IN $range\n";
        return 0;
    }
}


=pod

=head3 scan_type_id_to_text($typeID, $dbhr)

Determines the type of the scan identified by its scan type ID.

INPUTS:
  - $typeID: scan type ID
  - $dbhr  : database handle reference

RETURNS: Textual name of scan type

=cut

sub scan_type_id_to_text {
    my ($ID, $dbhr) = @_;

    my $query = "SELECT Scan_type FROM mri_scan_type WHERE ID='$ID'";
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();
    return 'unknown' unless $sth->rows;
    my @results = $sth->fetchrow_array();
    return $results[0];
}

=pod

=head3 scan_type_text_to_id($type, $dbhr)

Determines the type of the scan identified by scan type.

INPUTS:
  - $type: scan type
  - $dbhr: database handle reference

RETURNS: ID of the scan type

=cut

sub scan_type_text_to_id {
    my $type = shift;
    my $dbhr = shift;

    my $query = "SELECT ID FROM mri_scan_type WHERE Scan_type='$type'";
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();
    return &scan_type_text_to_id('unknown', $dbhr) unless $sth->rows;
    my @results = $sth->fetchrow_array();
    return $results[0];
}


=pod

=head3 in_range($value, $range_string)

Determines whether numerical value falls within the range described by range
string. Range string is a single range unit which follows the syntax
"X" or "X-Y".

INPUTS:
  - $value       : numerical value to evaluate
  - $range_string: the range to use

RETURNS: 1 if the value is in range, 0 otherwise

=cut

sub in_range
{
    my ($value, $range_string) = @_;
    chomp($value);

    return 0 unless $range_string;
    return 0 unless defined($value);

    chomp($range_string);
    if($range_string=~/^[0-9.]+$/) { ## single value element
        return 1 if &floats_are_equal($value, $range_string, $FLOAT_EQUALS_NB_DECIMALS);
    } else { ## range_string X-Y
        $range_string =~ /([0-9.]+)-([0-9.]+)/;
        return 1 if ($1 <= $value && $value <= $2)
            || &floats_are_equal($value, $1, $FLOAT_EQUALS_NB_DECIMALS)
            || &floats_are_equal($value, $2, $FLOAT_EQUALS_NB_DECIMALS);
    }

    ## if we've gotten this far, we're out of range.
    return 0;
}

=pod

=head3 floats_are_equal($f1, $f2, $nb_decimals)

Checks whether float 1 and float 2 are equal (considers only the first
C<$nb_decimals> decimals).

INPUTS:
  - $f1         : float 1
  - $f2         : float 2
  - $nb_decimals: the number of first decimals

RETURNS: 1 if the numbers are relatively equal, 0 otherwise

=cut

sub floats_are_equal {
    my($f1, $f2, $nb_decimals) = @_;

    return sprintf("%.${nb_decimals}g", $f1) eq sprintf("%.${nb_decimals}g", $f2);
}


=pod

=head3 range_to_sql($field, $range_string)

Generates a valid SQL WHERE expression to test C<$field> against
C<$range_string> using the same C<$range_string> syntax as C<&in_range()>.
It returns a scalar range SQL string appropriate to use as a WHERE condition
(C<SELECT ... WHERE range_to_sql(...)>).

INPUTS:
  - $field       : scalar field
  - $range_string: scalar range string that follows the same format as in
                    C<&in_range()>

RETURNS: scalar range SQL string

=cut

sub range_to_sql {
    my ($field, $range_string) = @_;
    chomp($field);

    # make sure there are no semi-colons in $field
    return '1' if $field=~/;/;

    # make sure string doesn't contain anything invalid
    return '1' unless $range_string=~/^[0-9,.-]+$/;

    my @ranges = split(/,/, $range_string);
    my $range = '';
    my $output = '';

    foreach $range (@ranges) {
        if($range=~/-/) { # it's a range
            my @ends = split(/-/, $range);
            $output .= ' OR ' unless $output eq '';
            $output .= "($ends[0]<=$field AND $field<=$ends[1])";
        } else { # it's a single value
            $output .= ' OR ' unless $output eq '';
            $output .= "$field=$range";
        }
    }

    return $output;
}


=pod

=head3 register_db($file_ref)

Registers the C<NeuroDB::File> object referenced by C<$file_ref> into the
database.

INPUT: file hash ref

RETURNS: 0 if the file is already registered, the new C<FileID> otherwise

=cut

sub register_db {
    my ($file_ref) = @_;
    my $file = $$file_ref;

    # get the database handle
    my $dbh = ${$file->getDatabaseHandleRef()};

    # retrieve the file's data
    my $fileData = $file->getFileData();

    # make sure this file isn't registered
    if(defined($fileData->{'FileID'}) && $fileData->{'FileID'} > 0) {
	return 0;
    }

    # build the insert query
    my $query = "INSERT INTO files SET ";

    foreach my $key ('File', 'SessionID','EchoTime', 'CoordinateSpace', 'OutputType', 'AcquisitionProtocolID', 'FileType', 'InsertedByUserID', 'Caveat', 'SeriesUID', 'TarchiveSource','SourcePipeline','PipelineDate','SourceFileID', 'ScannerID') {
        # add the key=value pair to the query
        $query .= "$key=".$dbh->quote($${fileData{$key}}).", ";
    }
    $query .= "InsertTime=UNIX_TIMESTAMP()";

    # run the query
    $dbh->do($query);
    my $fileID = $dbh->{'mysql_insertid'};
    $file->setFileData('FileID', $fileID);

    # retrieve the file's parameters
    my $params = $file->getParameters();

    # if there are any parameters to save
    if(scalar(keys(%$params)) > 0) {
	# build the insert query
	$query = "INSERT INTO parameter_file (FileID, ParameterTypeID, Value, InsertTime) VALUES ";
	foreach my $key (keys %$params) {
	    # skip the parameter if it is not defined
	    next unless defined $${params{$key}};

	    # add the parameter to the query
	    my $typeID = $file->getParameterTypeID($key);
	    my $value = '';
	    $value = $dbh->quote($${params{$key}});

	    if($query =~ /\)$/) { $query .= ",\n"; }

	    $query .= "($fileID, $typeID, $value, UNIX_TIMESTAMP())";
	}
	# run query
	$dbh->do($query);
    }
    return $fileID;
}

=pod

=head3 mapDicomParameters($file_ref)

Maps DICOM parameters to more meaningful names in the C<NeuroDB::File> object
referenced by C<$file_ref>.

INPUT: file hash ref

=cut

sub mapDicomParameters {
    my ($file_ref) = @_;
    my $file = $$file_ref;

    my (%map_hash);
        %map_hash=
    (
     xstep => 'xspace:step',
     ystep => 'yspace:step',
     zstep => 'zspace:step',

     xstart => 'xspace:start',
     ystart => 'yspace:start',
     zstart => 'zspace:start',

     study_date => 'dicom_0x0008:el_0x0020',
     series_date => 'dicom_0x0008:el_0x0021',
     acquisition_date => 'dicom_0x0008:el_0x0022',
     image_date => 'dicom_0x0008:el_0x0023',
     study_time => 'dicom_0x0008:el_0x0030',
     series_time => 'dicom_0x0008:el_0x0031',
     acquisition_time => 'dicom_0x0008:el_0x0032',
     image_time => 'dicom_0x0008:el_0x0033',
     modality => 'dicom_0x0008:el_0x0060',
     manufacturer => 'dicom_0x0008:el_0x0070',
     institution_name =>'dicom_0x0008:el_0x0080',
     study_description => 'dicom_0x0008:el_0x1030',
     series_description => 'dicom_0x0008:el_0x103e',
     operator_name => 'dicom_0x0008:el_0x1070',
     manufacturer_model_name => 'dicom_0x0008:el_0x1090',
     patient_name => 'dicom_0x0010:el_0x0010',
     patient_id => 'dicom_0x0010:el_0x0020',
     patient_dob => 'dicom_0x0010:el_0x0030',
     patient_sex => 'dicom_0x0010:el_0x0040',
     scanning_sequence => 'dicom_0x0018:el_0x0020',
     mr_acquisition_type => 'dicom_0x0018:el_0x0023',
     sequence_name => 'dicom_0x0018:el_0x0024',
     sequence_variant => 'dicom_0x0018:el_0x0021',
     slice_thickness => 'dicom_0x0018:el_0x0050',
     effective_series_duration => 'dicom_0x0018:el_0x0072',
     repetition_time => 'acquisition:repetition_time',
     echo_time => 'acquisition:echo_time',
     inversion_time => 'acquisition:inversion_time',
     number_of_averages => 'dicom_0x0018:el_0x0083',
     imaging_frequency => 'dicom_0x0018:el_0x0084',
     imaged_nucleus => 'dicom_0x0018:el_0x0085',
     echo_numbers => 'dicom_0x0018:el_0x0086',
     magnetic_field_strength => 'dicom_0x0018:el_0x0087',
     spacing_between_slices => 'dicom_0x0018:el_0x0088',
     number_of_phase_encoding_steps => 'dicom_0x0018:el_0x0089',
     echo_train_length => 'dicom_0x0018:el_0x0091',
     percent_sampling => 'dicom_0x0018:el_0x0093',
     percent_phase_field_of_view => 'dicom_0x0018:el_0x0094',
     pixel_bandwidth => 'dicom_0x0018:el_0x0095',
     device_serial_number => 'dicom_0x0018:el_0x1000',
     software_versions => 'dicom_0x0018:el_0x1020',
     protocol_name => 'dicom_0x0018:el_0x1030',
     spatial_resolution => 'dicom_0x0018:el_0x1050',
     fov_dimensions => 'dicom_0x0018:el_0x1149',
     receiving_coil => 'dicom_0x0018:el_0x1250',
     transmitting_coil => 'dicom_0x0018:el_0x1251',
     acquisition_matrix => 'dicom_0x0018:el_0x1310',
     phase_encoding_direction => 'dicom_0x0018:el_0x1312',
     variable_flip_angle_flag => 'dicom_0x0018:el_0x1315',
     sar => 'dicom_0x0018:el_0x1316',
     patient_position => 'dicom_0x0018:el_0x5100',
     study_instance_uid => 'dicom_0x0020:el_0x000d',
     series_instance_uid => 'dicom_0x0020:el_0x000e',
     study_id => 'dicom_0x0020:el_0x0010',
     series_number => 'dicom_0x0020:el_0x0011',
     acquisition_number => 'dicom_0x0020:el_0x0012',
     instance_number => 'dicom_0x0020:el_0x0013',
     image_position_patient => 'dicom_0x0020:el_0x0032',
     image_orientation_patient => 'dicom_0x0020:el_0x0037',
     frame_of_reference_uid => 'dicom_0x0020:el_0x0052',
     laterality => 'dicom_0x0020:el_0x0060',
     position_reference_indicator => 'dicom_0x0020:el_0x1040',
     slice_location => 'dicom_0x0020:el_0x1041',
     image_comments => 'dicom_0x0020:el_0x4000',
     rows => 'dicom_0x0028:el_0x0010',
     cols => 'dicom_0x0028:el_0x0011',
     pixel_spacing => 'dicom_0x0028:el_0x0030',
     bits_allocated => 'dicom_0x0028:el_0x0100',
     bits_stored => 'dicom_0x0028:el_0x0101',
     high_bit => 'dicom_0x0028:el_0x0102',
     pixel_representation => 'dicom_0x0028:el_0x0103',
     smallest_pixel_image_value => 'dicom_0x0028:el_0x0106',
     largest_pixel_image_value => 'dicom_0x0028:el_0x0107',
     pixel_padding_value => 'dicom_0x0028:el_0x0120',
     window_center => 'dicom_0x0028:el_0x1050',
     window_width => 'dicom_0x0028:el_0x1051',
     window_center_width_explanation => 'dicom_0x0028:el_0x1055'
    );

    # map parameters, removing the old params if they start with 'dicom'
    foreach my $key (keys %map_hash) {
	my $value = $file->getParameter($map_hash{$key});
	if(defined $value) {
	    $file->setParameter($key, $value);
	    $file->removeParameter($map_hash{$key}) if($map_hash{$key} =~ /^dicom/);
	}
    }
    my $patientName = $file->getParameter('patient_name');
    $patientName =~ s/[\?\(\)\\\/\^]//g;
    $file->setParameter('patient_name', $patientName);

    $patientName = $file->getParameter('patient:full_name');
    $patientName =~ s/[\?\(\)\\\/\^]//g;
    $file->setParameter('patient:full_name', $patientName);
}
=pod

=head3 findScannerID($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr, $register_new)

Finds the scanner ID for the scanner as defined by C<$manufacturer>, C<$model>,
C<$serialNumber>, C<$softwareVersion>, using the database attached to the DBI
database handle reference C<$dbhr>. If no scanner ID exists, one will be
created.

INPUTS:
  - $manufacturer   : scanner's manufacturer
  - $model          : scanner's model
  - $serialNumber   : scanner's serial number
  - $softwareVersion: scanner's software version
  - $centerID       : scanner's center ID
  - $dbhr           : database handle reference
  - $register_new   : if set, will call the function C<&registerScanner>

RETURNS: (int) scanner ID

=cut

sub findScannerID {
    my ($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr, $register_new) = @_;

    my $scanner_id = 0;

    my @results = ();
    my $query = "SELECT ID FROM mri_scanner WHERE Manufacturer=".$${dbhr}->quote($manufacturer)." AND Model=".$${dbhr}->quote($model)." AND Software=".$${dbhr}->quote($softwareVersion)." AND Serial_number=".$${dbhr}->quote($serialNumber);
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();
    @results = $sth->fetchrow_array();
    $scanner_id = $results[0] if $results[0];

    # only register new scanners when told to do so !!!
    if ($register_new) { $scanner_id = registerScanner($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr) unless $scanner_id };

    return $scanner_id;
}

=pod

=head3 registerScanner($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr)

Registers the scanner as defined by C<$manufacturer>, C<$model>,
C<$serialNumber>, C<$softwareVersion>, into the database attached to the DBI
database handle reference C<$dbhr>.

INPUTS:
  - $manufacturer   : scanner's manufacturer
  - $model          : scanner's model
  - $serialNumber   : scanner's serial number
  - $softwareVersion: scanner's software version
  - $centerID       : scanner's center ID
  - $dbhr           : database handle reference

RETURNS: (int) scanner ID

=cut

sub registerScanner {
    my ($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr) = @_;
    # my $scanner_id = 0;
    my @results = ();
    my $dbh = $$dbhr;
    my $candID = 'NULL';

    # find the CandID associated with this serial number
    my $query = "SELECT CandID FROM mri_scanner WHERE Serial_number=".$dbh->quote($serialNumber)." LIMIT 1";
    my $sth = $dbh->prepare($query);
    $sth->execute();
    if($sth->rows > 0) {
        my @row = $sth->fetchrow_array();
        $candID = $row[0];
    }
    $sth->finish();

    # create a new candidate for the scanner if it does not exist.
    if(!defined($candID) || ($candID eq 'NULL')) {
	$candID = createNewCandID($dbhr);
	$query = "INSERT INTO candidate (CandID, PSCID, CenterID, Date_active, Date_registered, UserID, Entity_type) VALUES ($candID, 'scanner', $centerID, NOW(), NOW(), 'NeuroDB::MRI', 'Scanner')";
	$dbh->do($query);
    }
    # register scanner as new
    $query = "INSERT INTO mri_scanner (Manufacturer, Model, Serial_number, Software, CandID) VALUES (".$dbh->quote($manufacturer).",".$dbh->quote($model).","
              .$dbh->quote($serialNumber).",".$dbh->quote($softwareVersion).",".$dbh->quote($candID).")";
    $dbh->do($query);
    # get id of scanner
    return $dbh->{'mysql_insertid'};
}

=pod

=head3 createNewCandID($dbhr)

Creates a new C<CandID>.

INPUT: database handle reference

RETURNS: C<CandID> (int)

=cut

sub createNewCandID {
    my ($dbhr) = @_;
    my $candID;

    my $sth = $${dbhr}->prepare("SELECT CandID FROM candidate WHERE CandID = ?");
    while(1) {
	$candID = int(rand 899999) + 100000;
	$sth->execute($candID);
	last if $sth->rows == 0;
    }

    return $candID;
}

=pod

=head3 getPSC($patientName, $dbhr)

Looks for the site alias using the C<session> table C<CenterID> as
a first resource, for the cases where it is created using the front-end,
otherwise, find the site alias in whatever field (usually C<patient_name>
or C<patient_id>) is provided, and return the C<MRI_alias> and C<CenterID>.

INPUTS:
  - $patientName: patient name
  - $dbhr       : database handle reference

RETURNS: a two element array:
  - first is the MRI alias of the PSC or "UNKN"
  - second is the C<CenterID> or 0

=cut

sub getPSC {
    my ($patientName, $dbhr) = @_;

    my $subjectIDsref = Settings::getSubjectIDs(
                            $patientName,
                            undef,
                            undef,
                            $dbhr
                        );
    my $PSCID = $subjectIDsref->{'PSCID'};
    my $visitLabel = $subjectIDsref->{'visitLabel'};

    ## Get the CenterID from the session table, if the PSCID and visit labels exist
    ## and could be extracted
    if ($PSCID && $visitLabel) {
    	my $query = "SELECT s.CenterID, p.MRI_alias FROM session s
                    JOIN psc p on p.CenterID=s.CenterID
                    JOIN candidate c on c.CandID=s.CandID
                    WHERE c.PSCID = ? AND s.Visit_label = ?";

        my $sth = $${dbhr}->prepare($query);
        $sth->execute($PSCID, $visitLabel);
        if ( $sth->rows > 0) {
            my $row = $sth->fetchrow_hashref();
            return ($row->{'MRI_alias'},$row->{'CenterID'});
        }
    }

    ## Otherwise, use the patient name to match it to the site alias or MRI alias
    $query = "SELECT CenterID, Alias, MRI_alias FROM psc WHERE mri_alias<>''";
    $sth = $${dbhr}->prepare($query);
    $sth->execute;

    while(my $row = $sth->fetchrow_hashref) {
        return ($row->{'MRI_alias'}, $row->{'CenterID'})
	    if ($patientName =~ /$row->{'Alias'}/i) || ($patientName =~ /$row->{'MRI_alias'}/i);
    }

    return ("UNKN", 0);
}

=pod

=head3 compute_hash($file_ref)

Semi-intelligently generates a hash (MD5 digest) for the C<NeuroDB::File> object
referenced by C<$file_ref>.

INPUT: file hash ref

RETURNS: the generated MD5 hash

=cut

sub compute_hash {
    my ($file_ref) = @_;
    my $file = $$file_ref;

    # open the file
    use Digest::MD5;
    my $filename = $file->getFileDatum('File');
    my $fileType = $file->getFileDatum('FileType');
    open FILE, "minctoraw -nonormalize $filename |" if $fileType eq 'mnc';
    open FILE, "<$filename" unless $fileType eq 'mnc';

    # add the file data to the digest
    my $ctx = Digest::MD5->new;
    $ctx->addfile(*FILE);

    # add some minc header fields that we care about to the digest
    if($fileType eq 'mnc') {
	$ctx->add($file->getParameter('patient:full_name'));          # PatientName
	$ctx->add($file->getParameter('study:start_time'));           # StudyDateTime
	$ctx->add($file->getParameter('patient:identification'));     # PatientID
    $ctx->add($file->getParameter('patient:sex'));                # Patient Sex
    $ctx->add($file->getParameter('patient:age'));                # Patient Age
	$ctx->add($file->getParameter('patient:birthdate'));          # Patient DOB
	$ctx->add($file->getParameter('study_instance_uid'));         # StudyInstanceUID
	$ctx->add($file->getParameter('series_description'));         # SeriesDescription
    if (defined $file->getParameter('processing:intergradient_rejected')) {
        $ctx->add($file->getParameter('processing:intergradient_rejected'));
    }
    # processing:intergradient_rejected minc field is the only field
    # separating a noRegQCedDTI and a QCedDTI minc file.
    }

    # finally generate the hex digest
    my $digest = $ctx->hexdigest;

    close FILE;
    return $digest;
}

=pod

=head3 is_unique_hash($file_ref)

Determines if the file is unique using the hash (MD5 digest) from the
C<NeuroDB::File> object referenced by C<$file_ref>.

INPUT: file hashref

RETURNS: 1 if the file is unique (or if hashes are not being tracked) or 0
otherwise.

=cut

sub is_unique_hash {
    my ($file_ref) = @_;
    my $file = $$file_ref;
    my $dbhr = $file->getDatabaseHandleRef();

    my $hash = $file->getParameter('md5hash');
    my $hashParameterTypeID = $file->getParameterTypeID('md5hash');

    # breaking gracefully (all files will be kept, basically) if we aren't tracking hashes...
    return 1 unless defined $hashParameterTypeID;

    my $sth = $${dbhr}->prepare("SELECT count(*) FROM parameter_file WHERE ParameterTypeID=$hashParameterTypeID AND Value='$hash'");
    $sth->execute();

    my @res = $sth->fetchrow_array();

    return 0 if $res[0] > 0;
    return 1;
}

=pod

=head3 make_pics($file_ref, $data_dir, $dest_dir, $horizontalPics)

Generates check pics for the Imaging Browser module for the C<NeuroDB::File>
object referenced by C<$file_ref>.

INPUTS:
  - $file_ref      : file hash ref
  - $data_dir      : data directory (e.g. C</data/$PROJECT/data>)
  - $dest_dir      : destination directory (e.g. C</data/$PROJECT/data/pic>)
  - $horizontalPics: boolean, whether to create horizontal pics (1) or not (0)

RETURNS: 1 if the pic was generated or 0 otherwise.

=cut

sub make_pics {
    my ($fileref, $data_dir, $dest_dir, $horizontalPics) = @_;
    my $file = $$fileref;
    my $dbhr = $file->getDatabaseHandleRef();

    my $sth = $${dbhr}->prepare("SELECT CandID, Visit_label FROM session WHERE ID=".$file->getFileDatum('SessionID'));
    $sth->execute();
    my $rowhr = $sth->fetchrow_hashref();

    my $acquisitionProtocol = scan_type_id_to_text($file->getFileDatum('AcquisitionProtocolID'), $dbhr);
    my $minc = $data_dir . '/' . $file->getFileDatum('File');
    my $mincbase = basename($minc);
    $mincbase =~ s/\.mnc(\.gz)?$//;

    my $pic = $dest_dir . '/' . $rowhr->{'CandID'};
    unless (-e $pic) { system("mkdir -p -m 770 $pic") == 0 or return 0; }
    my $tmpdir = tempdir( CLEANUP => 1 );

    # if the file has a fileid, add that to the filename
    my $fileID = $file->getFileDatum('FileID');
    $mincbase .= "_$fileID" if defined $fileID;

    my $check_pic_filename = $mincbase."_check.jpg";
    my $do_horizontal = "";
    $do_horizontal = "-horizontal" if $horizontalPics;
    my $cmd = "$FindBin::Bin/bin/mincpik -triplanar $do_horizontal $minc MIFF:- | convert -box black -font Courier -pointsize 12 -stroke white -draw 'text 10,15 \"$rowhr->{'CandID'}.$rowhr->{'Visit_label'}.$acquisitionProtocol\"' MIFF:- $pic/$check_pic_filename";
    `$cmd`;
    # update mri table
    $file->setParameter('check_pic_filename', $rowhr->{'CandID'}.'/'.$check_pic_filename);
    return 1;
}

=pod

=head3 make_nii($fileref, $data_dir)

Creates NIfTI files associated with MINC files and append its path to the
C<parameter_file> table using the C<parameter_type> C<check_nii_filename>.

INPUTS:
  - $fileref : file hash ref
  - $data_dir: data directory (e.g. C</data/$PROJECT/data>)

=cut

sub make_nii {
    my ($fileref, $data_dir)  = @_;

    # Get MINC filename and NIfTI filename
    my $file = $$fileref;
    my $minc  = $file->getFileDatum('File');
    my ($nifti, $bval_file, $bvec_file) = ($minc) x 3;
    $nifti     =~ s/mnc$/nii/;
    $bval_file =~ s/mnc$/bval/;
    $bvec_file =~ s/mnc$/bvec/;

    #  mnc2nii command
    my $m2n_cmd = "mnc2nii -nii -quiet $data_dir/$minc $data_dir/$nifti";
    system($m2n_cmd);

    # create complementary nifti files for DWI acquisitions
    my $bval_success = create_dwi_nifti_bval_file($fileref, "$data_dir/$bval_file");
    my $bvec_success = create_dwi_nifti_bvec_file($fileref, "$data_dir/$bvec_file");

    # update mri table (parameter_file table)
    $file->setParameter('check_nii_filename', $nifti);
    $file->setParameter('check_bval_filename', $bval_file) if $bval_success;
    $file->setParameter('check_bvec_filename', $bvec_file) if $bvec_success;
}


=pod

=head3 create_dwi_nifti_bval_file($file_ref, $bval_file)

Creates the NIfTI C<.bval> file required for DWI acquisitions based on the
returned value of C<acquisition:bvalues>.

INPUTS:
  - $file_ref : file hash ref
  - $bval_file: path to the C<.bval> file to write into

RETURNS:
  - undef if no C<acquisition:bvalues> were found (skipping the creation
    of the C<.bval> file since there is nothing to write into)
  - 1 after the C<.bval> file was created

=cut

sub create_dwi_nifti_bval_file {
    my ($file_ref, $bval_file) = @_;

    # grep bvals from the header acquisition:bvalues
    my $file  = $$file_ref;
    my $bvals = $file->getParameter('acquisition:bvalues');

    return undef unless $bvals;

    # clean up the bvals string
    $bvals =~ s/\.\,//g; # remove all '.,' from the string
    $bvals =~ s/\.$//;   # remove the last trailing '.' from the string

    # print bvals into bval_file
    open(FILE, '>', $bval_file) or die "Could not open file $bval_file: $!\n";
    print FILE $bvals;
    close FILE;

    return -e $bval_file;
}


=pod

=head3 create_dwi_nifti_bvec_file($file_ref, $bvec_file)

Creates the NIfTI C<.bvec> file required for DWI acquisitions based on the
returned value of C<acquisition:direction_x>, C<acquisition:direction_y> and
C<acquisition:direction_z>.

INPUTS:
  - $file_ref : file hash ref
  - $bvec_file: path to the C<.bvec> file to write into

RETURNS:
  - undef if no C<acquisition:direction_x>, C<acquisition:direction_y> and
    C<acquisition:direction_z> were found (skipping the creation
    of the C<.bvec> file since there is nothing to write into)
  - 1 after the C<.bvec> file was created

=cut

sub create_dwi_nifti_bvec_file {
    my ($file_ref, $bvec_file) = @_;

    # grep bvecs from headers acquisition:direction_x, y and z
    my $file  = $$file_ref;
    my @bvecs = (
        $file->getParameter('acquisition:direction_x'),
        $file->getParameter('acquisition:direction_y'),
        $file->getParameter('acquisition:direction_z')
    );

    return undef unless ($bvecs[0] && $bvecs[1] && $bvecs[2]);

    # loop through all bvecs, clean them up and print them into the bvec file
    s/^\"+|\"$//g for @bvecs;
    open(OUT, '>', $bvec_file) or die "Cannot write to file $bvec_file: $!\n";
    print OUT map { "$_\n" } @bvecs;
    close(OUT);

    return -e $bvec_file;
}


=pod

=head3 make_minc_pics($dbhr, $TarchiveSource, $profile, $minFileID, $debug, $verbose)

Creates pics associated with MINC files.

INPUTS:
  - $dbhr          : database handle reference
  - $TarchiveSource: C<TarchiveID> of the DICOM study
  - $profile       : the profile file (typically named C<prod>)
  - $minFileID     : smaller C<FileID> to be used to run C<mass_pic.pl>
  - $debug         : boolean, whether in debug mode (1) or not (0)
  - $verbose       : boolean, whether in verbose mode (1) or not (0)

=cut

sub make_minc_pics {
    my ($dbhr, $TarchiveSource, $profile, $minFileID, $debug, $verbose) = @_;
    my $where = "WHERE TarchiveSource = ? ";
    my $query = "SELECT Min(FileID) AS min, Max(FileID) as max FROM files ";
    $query    = $query . $where;
    if ($debug) {
        print $query . "\n";
    }
    my $sth   = $${dbhr}->prepare($query);
    $sth->execute($TarchiveSource);
    print "TarchiveSource is " . $TarchiveSource . "\n";

    my $script = undef;
    my $output = undef;
    my @row = $sth->fetchrow_array();
    if (@row) {
        $script = "mass_pic.pl -minFileID $row[$minFileID] -maxFileID $row[1] ".
                     "-profile $profile";
        if ($verbose) {
            $script .= " -verbose";
	}

        ############################################################
        ## Note: system call returns the process ID ################
        ## To get the actual exit value, shift right by eight as ###
        ## done below ##############################################
        ############################################################
        $output = system($script);
        $output = $output >> 8;
    }
}

=pod

=head3 DICOMDateToUnixTimestamp($dicomDate>

Converts a DICOM date field (YYYYMMDD) into a unix timestamp.

INPUT: DICOM date to convert

RETURNS: a unix timestamp (integer) or 0 if something went wrong

=cut

sub DICOMDateToUnixTimestamp {
    my ($dicomDate) = @_;

    if($dicomDate =~ /(\d{4})-?(\d{2})-?(\d{2})/) {
        # generate the unix timestamp
        my $unixTime = timelocal(0, 0, 12, $3, $2, $1);

        # return the timestamp
        return $unixTime

    } else {
        # an invalid date format was passed in, so return 0
        return 0;
    }
}

=pod

=head3 lookupCandIDFromPSCID($pscid, $dbhr)

Looks up the C<CandID> for a given C<PSCID>.

INPUTS:
  - $pscid: candidate's C<PSCID>
  - $dbhr : database handle reference

RETURNS: the C<CandID> or 0 if the C<PSCID> does not exist

=cut

sub lookupCandIDFromPSCID {
    my ($pscid, $dbhr) = @_;
    my $candid = 0;
    my $sth = $${dbhr}->prepare("SELECT CandID FROM candidate WHERE PSCID=".$${dbhr}->quote($pscid));
    $sth->execute();
    if($sth->rows > 0) {
        my @row = $sth->fetchrow_array();
        $candid = int($row[0]);
    }
    return $candid;
}

sub my_trim {
	my ($str) = @_;
	$str =~ s/^\s+//;
	$str =~ s/\s+$//;
	return $str;
}


=pod

=head3 isDicomImage(@files_list)

This method checks whether the files given as an argument are DICOM images or not.
It will return a hash with the file path as keys and true or false as values (the
value will be set to true if the file is a DICOM image, otherwise it will be set to
false).

INPUT: array with full path to the DICOM files

RETURNS:
  - %isDicomImage: hash with file path as keys and true or false as values (true
                   if the file is a DICOM image file, false otherwise)

=cut

sub isDicomImage {
    my (@files_list) = @_;

    # For now, the files list need to be written in a temporary file so that the
    # command does not fail on large amount of files. If doing directly
    # `ls @files_list | xargs file` then the argument list is too long at it does
    # not return one file per line but many files in one line. Writing in a
    # temporary file on which we run the command `cat` seems to be the only option
    # that works at the moment...
    my $tmp_file = $ENV{'TMPDIR'} . "/tmp_list";
    open(my $fh, '>', $tmp_file) or die "Could not open file '$tmp_file' $!";
    foreach my $file (@files_list) {
        printf $fh "%s\n", quotemeta($file);
    }
    close($fh);

    my $cmd = "cat $tmp_file | xargs file";
    my @file_types = `$cmd`;
    unlink $tmp_file;

    my %isDicomImage;
    foreach my $line (@file_types) {
        my ($file, $type) = split(':', $line);

        unless ($type =~ /DICOM medical imaging data$/) {
            $isDicomImage{$file} = 0;
            next;
        }

        my $dicom = DICOM->new();
        $dicom->fill($file);
        if ($dicom->value('7fe0','0010')) {
            $isDicomImage{$file} = 1;
        } else {
            $isDicomImage{$file} = 0;
        }
    }

    return \%isDicomImage;
}


=pod

=head3 get_trashbin_file_rel_path($file)

Determines and returns the relative path of a file moved to trashbin at the end of
the insertion pipeline.

INPUT: path to a given file

RETURNS: the relative path of the file moved to the trashbin directory

=cut

sub get_trashbin_file_rel_path {
    my ($file) = @_;

    my @directories  = split(/\//, $file);
    my $new_rel_path = "trashbin"
                       . "/" . $directories[$#directories-1]
                       . "/" . $directories[$#directories];

    return $new_rel_path;
}

1;

__END__


=pod

=head1 TO DO

Fix comments written as #fixme in the code.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2003-2004 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

=head1 AUTHORS

Jonathan Harlap <jharlap@bic.mni.mcgill.ca>,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience
=cut

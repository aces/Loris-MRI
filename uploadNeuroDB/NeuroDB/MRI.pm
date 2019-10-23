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

use NeuroDB::objectBroker::MriScanTypeOB;
use NeuroDB::objectBroker::MriScannerOB;
use NeuroDB::objectBroker::PSCOB;
use NeuroDB::UnexpectedValueException;

$VERSION = 0.2;
@ISA = qw(Exporter);

# Number of decimals considered when testing if two floats are equal
$FLOAT_EQUALS_NB_DECIMALS = 4;

@EXPORT = qw();
@EXPORT_OK = qw(identify_scan in_range get_headers get_info get_ids get_objective identify_scan_db scan_type_text_to_id scan_type_id_to_text register_db get_header_hash get_scanner_id get_psc compute_hash is_unique_hash make_pics select_volume);

=pod

=head3 subjectIDExists($ID_type, ID_value, $dbhr)

Verifies that the subject ID (C<CandID> or C<PSCID>) exists.

INPUTS:
  - $ID_type : type of candidate ID (C<CandID> or C<PSCID>)
  - $ID_value: value of the candidate ID
  - $dbhr    : the database handle reference

RETURNS: 1 if the ID exists in the candidate table, 0 otherwise

=cut

sub subjectIDExists {
    my ($ID_type, $ID_value, $dbhr) = @_;

    # check if ID already exists in the candidate table
    my $query = "SELECT COUNT(*) AS idExists FROM candidate WHERE $ID_type=?";
    my $sth   = $${dbhr}->prepare($query);
    $sth->execute($ID_value);
    my $rowhd = $sth->fetchrow_hashref();

    return $rowhd->{'idExists'} > 0;
}

=pod

=head3 getScannerCandID($scannerID, $db)

Retrieves the candidate (C<CandID>) for the given scanner.

INPUTS: the scanner ID and the database object

RETURNS: the C<CandID> or (if none exists) undef

=cut

sub getScannerCandID {
    my ($scannerID, $db) = @_;
    
    my $mriScannerOB = 
        NeuroDB::objectBroker::MriScannerOB->new(db => $db);
    my $resultRef = $mriScannerOB->get({ID => $scannerID});
    return @$resultRef ? $resultRef->[0]->{'CandID'} : undef;
}

=pod

=head3 getSessionID($subjectIDref, $studyDate, $dbhr, $objective, $noStagingCheck)

Gets (or creates) the session ID, given CandID and visitLabel (contained
inside the hashref C<$subjectIDref>). 

INPUTS:
  - $subjectIDref: hash reference of subject IDs
  - $studyDate   : study date
  - $dbhr        : database handle reference
  - $objective   : the objective of the study
  - $db          : database object

RETURNS: the session ID of the visit

=cut

sub getSessionID {
    my ($subjectIDref, $studyDate, $dbhr, $objective, $db) = @_;
    my ($sessionID, $studyDateJD);
    my ($query, $sth);
    my $dbh = $$dbhr;

# find a matching timepoint
    $query = "SELECT ID, Date_visit, Visit FROM session WHERE CandID=$subjectIDref->{'CandID'} AND LOWER(Visit_label)=LOWER(".$dbh->quote($subjectIDref->{'visitLabel'}).") AND Active='Y'";
    $sth = $dbh->prepare($query);
    $sth->execute();

##### if it finds an existing session it does this:
    if($sth->rows > 0) {
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
	}

	# check dates of other files
	if(defined($studyDateJD)) {
	    # get the set of files 
	    $query = "SELECT FileID FROM files WHERE SessionID=$sessionID AND FileType='mnc' AND OutputType='native'";
	    $sth = $dbh->prepare($query);
	    $sth->execute();

	    if($sth->rows > 0) {
		my @files = ();
		while(my $filehr = $sth->fetchrow_hashref()) { push @files, $filehr->{'FileID'}; }
		$sth->finish();

	    }
	}

#####  if there is no existing session, which always happens if you create candidates based on incoming data
    } else {

	# determine the visit number and centerID for the next session
        my $newVisitNo = 0;
        my $centerID = 0;

        if($subjectIDref->{'visitLabel'} =~ /PHA/i or $subjectIDref->{'visitLabel'} =~ /TEST/i) {
	    # calibration data (PHANTOM_site_date | LIVING_PHANTOM_site_date | *test*)
            my @pscInfo = getPSC($subjectIDref->{'visitLabel'}, $dbhr, $db);
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
                $query = "SELECT RegistrationCenterID AS CenterID FROM candidate "
                         . "WHERE CandID=" . $dbh->quote($subjectIDref->{'CandID'});
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
	if(defined($studyDateJD)) {
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
		} # end if sth->rows (files)
	    } # end if sth->rows (sessionIDs)
	} # end if defined studyDateJD
    }

    return ($sessionID, $requiresStaging);
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

=head3 identify_scan_db($center_name, $objective, $fileref, $dbhr, $db, $minc_location)

Determines the type of the scan described by MINC headers based on
C<mri_protocol> table in the database.

INPUTS:
  - $center_name   : center's name
  - $objective     : objective of the study
  - $fileref       : file hash ref
  - $dbhr          : database handle reference
  - $db            : database object
  - $minc_location : location of the MINC files

RETURNS: textual name of scan type from the C<mri_scan_type> table

=cut

sub identify_scan_db {

    my  ($psc, $subjectref, $tarchiveInfoRef, $fileref, $dbhr, $db, $minc_location
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
    my $image_type = ${fileref}->getParameter('acquisition:image_type');

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
    my $mriScannerOB = NeuroDB::objectBroker::MriScannerOB->new( db => $db );
    my $resultsRef = $mriScannerOB->get( {
        Manufacturer  => $fileref->getParameter('manufacturer'),
        Model         => $fileref->getParameter('manufacturer_model_name'),
        Serial_number => $fileref->getParameter('device_serial_number'),
        Software      => $fileref->getParameter('software_versions')
	});
    
    # default ScannerID to 0 if we have no better clue.
    my $ScannerID = @$resultsRef> 0 ? $resultsRef->[0]->{'ID'} : 0;
    
    # get the list of protocols for a site their scanner and subproject
    $query = "SELECT *
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
        my $sd_regex          = $rowref->{'series_description_regex'};
        my $tr_min     = $rowref->{'TR_min'};
        my $tr_max     = $rowref->{'TR_max'};
        my $te_min     = $rowref->{'TE_min'};
        my $te_max     = $rowref->{'TE_max'};
        my $ti_min     = $rowref->{'TI_min'};
        my $ti_max     = $rowref->{'TI_max'};
        my $xspace_min = $rowref->{'xspace_min'};
        my $xspace_max = $rowref->{'xspace_max'};
        my $yspace_min = $rowref->{'yspace_min'};
        my $yspace_max = $rowref->{'yspace_max'};
        my $zspace_min = $rowref->{'zspace_min'};
        my $zspace_max = $rowref->{'zspace_max'};
        my $xstep_min  = $rowref->{'xstep_min'};
        my $xstep_max  = $rowref->{'xstep_max'};
        my $ystep_min  = $rowref->{'ystep_min'};
        my $ystep_max  = $rowref->{'ystep_max'};
        my $zstep_min  = $rowref->{'zstep_min'};
        my $zstep_max  = $rowref->{'zstep_max'};
        my $time_min   = $rowref->{'time_min'};
        my $time_max   = $rowref->{'time_max'};
        my $slice_thick_min = $rowref->{'slice_thickness_min'};
        my $slice_thick_max = $rowref->{'slice_thickness_max'};

        if(0) {
            print "\tChecking ".&scan_type_id_to_text($rowref->{'Scan_type'}, $db)." ($rowref->{'Scan_type'}) ($series_description =~ $sd_regex)\n";
            print "\t";
            if($sd_regex && ($series_description =~ /$sd_regex/i)) {
                print "series_description\t";
            }
            print &in_range($tr,     "$tr_min-$tr_max")         ? "TR\t"     : '';
            print &in_range($te,     "$te_min-$te_max")         ? "TE\t"     : '';
            print &in_range($ti,     "$ti_min-$ti_max")         ? "TI\t"     : '';
            print &in_range($xspace, "$xspace_min-$xspace_max") ? "xspace\t" : '';
            print &in_range($yspace, "$yspace_min-$yspace_max") ? "yspace\t" : '';
            print &in_range($zspace, "$zspace_min-$zspace_max") ? "zspace\t" : '';
            print &in_range($xstep,  "$xstep_min-$xstep_max")   ? "xstep\t"  : '';
            print &in_range($ystep,  "$ystep_min-$ystep_max")   ? "ystep\t"  : '';
            print &in_range($zstep,  "$zstep_min-$zstep_max")   ? "zstep\t"  : '';
            print &in_range($time,   "$time_min-$time_max")     ? "time\t"   : '';
            print &in_range($slice_thickness, "$slice_thick_min-$slice_thick_max") ? "ST\t" : '';
            print "\n";
        }

	    if ($sd_regex) {
            if ($series_description =~ /$sd_regex/i) {
                return &scan_type_id_to_text($rowref->{'Scan_type'}, $db);
            }

	    } else {
         	if ( &in_range($tr,              "$tr_min-$tr_max"                  )
              && &in_range($te,              "$te_min-$te_max"                  )
              && &in_range($ti,              "$ti_min-$ti_max"                  )
              && &in_range($xspace,          "$xspace_min-$xspace_max"          )
              && &in_range($yspace,          "$yspace_min-$yspace_max"          )
              && &in_range($zspace,          "$zspace_min-$zspace_max"          )
              && &in_range($xstep,           "$xstep_min-$xstep_max"            )
              && &in_range($ystep,           "$ystep_min-$ystep_max"            )
              && &in_range($zstep,           "$zstep_min-$zstep_max"            )
              && &in_range($time,            "$time_min-$time_max"              )
              && &in_range($slice_thickness, "$slice_thick_min-$slice_thick_max")
              && (!$rowref->{'image_type'} || $image_type =~ /\Q$rowref->{'image_type'}\E/i)
            ) {
                    return &scan_type_id_to_text($rowref->{'Scan_type'}, $db);
            }
        }
    }

    # if we got here, we're really clueless...
    insert_violated_scans(
        $dbhr,   $series_description, $minc_location,   $patient_name,
        $candid, $pscid,              $tr,              $te,
        $ti,     $slice_thickness,    $xstep,           $ystep,
        $zstep,  $xspace,             $yspace,          $zspace,
        $time,   $seriesUID,          $tarchiveID,      $image_type
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
  - $tarchiveID     : C<TarchiveID> of the DICOM archive from which this file is derived
  - $image_type     : the C<image_type> header value of the image

=cut

sub insert_violated_scans {

    my ($dbhr,   $series_description, $minc_location, $patient_name,
        $candid, $pscid,              $tr,            $te,
        $ti,     $slice_thickness,    $xstep,         $ystep,
        $zstep,  $xspace,             $yspace,        $zspace,
        $time,   $seriesUID,          $tarchiveID,    $image_type) = @_;

    # determine the future relative path when the file will be moved to
    # data_dir/trashbin at the end of the script's execution
    my $file_rel_path = get_trashbin_file_rel_path($minc_location);

    (my $query = <<QUERY) =~ s/\n//gm;
  INSERT INTO mri_protocol_violated_scans (
    CandID,             PSCID,         TarchiveID,            time_run,
    series_description, minc_location, PatientName,           TR_range,
    TE_range,           TI_range,      slice_thickness_range, xspace_range,
    yspace_range,       zspace_range,  xstep_range,           ystep_range,
    zstep_range,        time_range,    SeriesUID,             image_type
  ) VALUES (
    ?, ?, ?, now(),
    ?, ?, ?, ?,
    ?, ?, ?, ?,
    ?, ?, ?, ?,
    ?, ?, ?, ?
  )
QUERY

    my $sth = $${dbhr}->prepare($query);
    my $success = $sth->execute(
        $candid,        $pscid,           $tarchiveID, $series_description,
        $file_rel_path, $patient_name,    $tr,         $te,
        $ti,            $slice_thickness, $xspace,     $yspace,
        $zspace,        $xstep,           $ystep,      $zstep,
        $time,          $seriesUID,       $image_type
    );

}


=pod

=head3 scan_type_id_to_text($typeID, $db)

Determines the type of the scan identified by its scan type ID.

INPUTS:
  - $typeID: scan type ID
  - $db    : database object

RETURNS: Textual name of scan type

=cut

sub scan_type_id_to_text {
    my ($typeID, $db) = @_;

    my $mriScanTypeOB = NeuroDB::objectBroker::MriScanTypeOB->new(
        db => $db
    );
    my $mriScanTypeRef = $mriScanTypeOB->get(0, { ID => $typeID });
    
    # This is just to make sure that there is a scan type in the DB
    # with name 'unknown' in case we can't find the one with ID $ID
    $mriScanTypeOB->get(0, { Scan_type => 'unknown' }) if !@$mriScanTypeRef;

    if(!@$mriScanTypeRef) {
        NeuroDB::UnexpectedValueException->throw(
            errorMessage => sprintf(
                "Unknown acquisition protocol ID %d and scan type 'unknown' does not exist in the database",
                $typeID
            ) 
        );
    }
    
    return $mriScanTypeRef->[0]->{'Scan_type'};
}

=pod

=head3 scan_type_text_to_id($type, $db)

Determines the type of the scan identified by scan type.

INPUTS:
  - $type: scan type
  - $db  : database object

RETURNS: ID of the scan type

=cut

sub scan_type_text_to_id {
    my($type, $db) = @_;

    my $mriScanTypeOB = NeuroDB::objectBroker::MriScanTypeOB->new(
        db => $db
    );
    my $mriScanTypeRef = $mriScanTypeOB->get(
        0, { Scan_type => $type }
    );
    $mriScanTypeRef = $mriScanTypeOB->get(0, { Scan_type => 'unknown' }) if !@$mriScanTypeRef;
    if(!@$mriScanTypeRef) {
        NeuroDB::UnexpectedValueException->throw(
            errorMessage => sprintf(
                "Unknown acquisition protocol %s and scan type 'unknown' does not exist in the database",
                $type
            ) 
        );
    }
    
    return $mriScanTypeRef->[0]->{'ID'};
}


=pod

=head3 in_range($value, $range_string)

Determines whether numerical value falls within the range described by range
string. Range string is a single range unit which follows the syntax
"X" or "X-Y".

Note that if C<$range_string>="-", it means that the value in the database are
NULL for both the MIN and MAX columns, therefore we do not want to restrict the
range for this field and the function will return 1.

INPUTS:
  - $value       : numerical value to evaluate
  - $range_string: the range to use

RETURNS: 1 if the value is in range or the range is undef, 0 otherwise

=cut

sub in_range
{
    my ($value, $range_string) = @_;
    chomp($value);

    # return 1 if the range_string = "-" as it means that max & min values were undef
    # when calling the in_range function and we should not restrict on that field
    return 1 if $range_string eq "-";

    # grep the min and max values of the range
    my @range = split(/-/, $range_string);
    my $min   = $range[0];
    my $max   = $range[1];

    # returns 1 if both $min and $max are undefined as in infinity range
    return 1 if (!defined $min && !defined $max);

    # returns 1 if min & max are defined and value is within the range [min-max]
    return 1 if (defined $min && defined $max)
        && ( ($min <= $value && $value <= $max)
             || &floats_are_equal($value, $min, $FLOAT_EQUALS_NB_DECIMALS)
             || &floats_are_equal($value, $max, $FLOAT_EQUALS_NB_DECIMALS)
        );

    # returns 1 if only min is defined and value is <= to $min
    return 1 if (defined $min and !defined $max)
        && ($min <= $value || &floats_are_equal($value, $min, $FLOAT_EQUALS_NB_DECIMALS));

    # returns 1 if only max is defined and value is >= to $max
    return 1 if (defined $max and !defined $min)
            && ($value <= $max || &floats_are_equal($value, $max, $FLOAT_EQUALS_NB_DECIMALS));

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

=head3 findScannerID($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr, $register_new, $db)

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
  - $db             : database object

RETURNS: (int) scanner ID

=cut

sub findScannerID {
    my ($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr, $register_new, $db) = @_;

    my $mriScannerOB = NeuroDB::objectBroker::MriScannerOB->new( db => $db );
    my $resultsRef = $mriScannerOB->get( {
		Manufacturer  => $manufacturer,
		Model         => $model,
		Software      => $softwareVersion,
		Serial_number => $serialNumber
	});
	
	# Scanner exists
    return $resultsRef->[0]->{'ID'} if @$resultsRef;

    # Scanner does not exist and we don't want to register a new one: ID defaults to 0
    return 0 if !$register_new;
    
    # only register new scanners when told to do so !!!
    my $scanner_id = registerScanner($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr, $db);

    return $scanner_id;
}

=pod

=head3 registerScanner($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr, $db)

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
  - $db             : database object

RETURNS: (int) scanner ID

=cut

sub registerScanner {
    my ($manufacturer, $model, $serialNumber, $softwareVersion, $centerID, $dbhr, $db) = @_;
    # my $scanner_id = 0;
    my @results = ();
    my $dbh = $$dbhr;
    
    my $mriScannerOB = NeuroDB::objectBroker::MriScannerOB->new( db => $db );
    my $resultsRef = $mriScannerOB->get( { Serial_number => $serialNumber } );
    my $candID = @$resultsRef > 0 ? $resultsRef->[0]->{'CandID'} : undef;

    # create a new candidate for the scanner if it does not exist.
    if(!defined($candID) || ($candID eq 'NULL')) {
	    $candID = createNewCandID($dbhr);
	    $query = "INSERT INTO candidate "
                 . "(CandID,          PSCID,  RegistrationCenterID, Date_active,  "
                 . " Date_registered, UserID, Entity_type                       ) "
                 . "VALUES "
                 . "($candID, 'scanner',      $centerID,  NOW(),   "
                 . " NOW(),   'NeuroDB::MRI', 'Scanner'          ) ";
	    $dbh->do($query);
    }	
    
    return $mriScannerOB->insertOne({
		Manufacturer  => $manufacturer,
		Model         => $model,
		Serial_number => $serialNumber,
		Software      => $softwareVersion,
		CandID        => $candID
	});
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

=head3 getPSC($patientName, $dbhr, $db)

Looks for the site alias using the C<session> table C<CenterID> as
a first resource, for the cases where it is created using the front-end,
otherwise, find the site alias in whatever field (usually C<patient_name>
or C<patient_id>) is provided, and return the C<MRI_alias> and C<CenterID>.

INPUTS:
  - $patientName: patient name
  - $dbhr       : database handle reference
  - $db         : database object

RETURNS: a two element array:
  - first is the MRI alias of the PSC or "UNKN"
  - second is the C<CenterID> or 0

=cut

sub getPSC {
    my ($patientName, $dbhr, $db) = @_;

    my $subjectIDsref = Settings::getSubjectIDs(
                            $patientName,
                            undef,
                            undef,
                            $dbhr,
                            $db
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
    my $pscOB   = NeuroDB::objectBroker::PSCOB->new( db => $db );
    my $pscsRef = $pscOB->get({ MRI_alias => { NOT => '' } });

    foreach my $psc (@$pscsRef) {
        if ($patientName =~ /$psc->{'Alias'}/i || $patientName =~ /$psc->{'MRI_alias'}/i) {
            return ($psc->{'MRI_alias'}, $psc->{'CenterID'}); 
		}
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
  - $db            : database object used to interact with the database.

RETURNS: 1 if the pic was generated or 0 otherwise.

=cut

sub make_pics {
    my ($fileref, $data_dir, $dest_dir, $horizontalPics, $db) = @_;
    my $file = $$fileref;
    my $dbhr = $file->getDatabaseHandleRef();

    my $sth = $${dbhr}->prepare("SELECT CandID, Visit_label FROM session WHERE ID=".$file->getFileDatum('SessionID'));
    $sth->execute();
    my $rowhr = $sth->fetchrow_hashref();
    
    my $acquisitionProtocol = scan_type_id_to_text($file->getFileDatum('AcquisitionProtocolID'), $db);
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
    my $cmd = "$FindBin::Bin/bin/mincpik.pl -triplanar $do_horizontal $minc MIFF:- | convert -box black -font Courier -pointsize 12 -stroke white -draw 'text 10,15 \"$rowhr->{'CandID'}.$rowhr->{'Visit_label'}.$acquisitionProtocol\"' MIFF:- $pic/$check_pic_filename";
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
    $nifti         =~ s/mnc$/nii/;
    $bval_file     =~ s/mnc$/bval/;
    $bvec_file     =~ s/mnc$/bvec/;

    #  mnc2nii command
    my $m2n_cmd  = "mnc2nii -nii -quiet $data_dir/$minc $data_dir/$nifti";
    system($m2n_cmd);

    # gzip the NIfTI file
    my $gzip_nifti = gzip_file("$data_dir/$nifti");
    $gzip_nifti    =~ s%$data_dir/%%g;

    # create complementary nifti files for DWI acquisitions
    my $bval_success = create_dwi_nifti_bval_file($fileref, "$data_dir/$bval_file");
    my $bvec_success = create_dwi_nifti_bvec_file($fileref, "$data_dir/$bvec_file");

    # update mri table (parameter_file table)
    $file->setParameter('check_nii_filename',  $gzip_nifti) if -e $gzip_nifti;
    $file->setParameter('check_bval_filename', $bval_file) if $bval_success;
    $file->setParameter('check_bvec_filename', $bvec_file) if $bvec_success;
}


=pod

=head3 gzip_file($file)

Gzip the file given as input and return the path of the gzipped file.

INPUT: file to be gzipped

RETURNS: path of the gzipped file (or undef if file not found)

=cut

sub gzip_file {
    my ($file) = @_;

    return undef unless (-e $file);

    my $gzip_cmd = "gzip $file";
    system($gzip_cmd);

    (-e "$file.gz") ? return "$file.gz" : undef;
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

sub my_trim {
	my ($str) = @_;
	$str =~ s/^\s+//;
	$str =~ s/\s+$//;
	return $str;
}

=pod

=head3 fetch_minc_header_info($minc, $field, $keep_semicolon, $get_arg_name)

Function that fetches header information in MINC file.

INPUTS:
  - $minc : MINC file
  - $field: string to look for in MINC header (or 'all' to grep all headers)
  - $keep_semicolon: if set, keeps ";" at the end of extracted value
  - $get_arg_name  : if set, returns the MINC header field name


RETURNS: value (or header name) of the field found in the MINC header

=cut

sub fetch_header_info {
    my ($minc, $field, $keep_semicolon, $header_part) = @_;

    my $value;
    if ($field eq 'all') {
        # run mincheader and return all the content of the command
        $value = `mincheader -data "$minc"`;
    } else {
        # fetch a particular header value, remove extra spaces and optionally
        # the semicolon
        my $cut_opt = $header_part ? "-f1" : "-f2";
        my $val = `mincheader -data "$minc" | grep "$field" | cut -d= $cut_opt | tr '\n' ' '`;
        $value  = my_trim($val) if $val !~ /^\s*"*\s*"*\s*$/;
        return undef unless ($value);  # return undef if no value found
        $value =~ s/"//g;  # remove "
        $value =~ s/;// unless ($keep_semicolon);  # remove ";"
    }

    return $value;
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

=pod

=head3 deleteFiles(@files)

Deletes a set of files from the file system. A warning will be issued for every file
that could not be deleted.

INPUTS:

  - @files: list of files to delete.
  
=cut
sub deleteFiles {
	my(@files) = @_;
	
	foreach(@files) {
		unlink $_ or warn "Warning! File '$_' could not be deleted: $!\n";
	}
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

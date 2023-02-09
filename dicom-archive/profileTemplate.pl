=pod
# -----------------------------------------------------------------------------------------------
  WHAT THIS IS:
  Although someone might argue that this is not a config file anymore... this is in fact a config
  WHAT THIS IS FOR:
  For users of the neurodb system... or actually the ones that believe in tarchiving their universe
  WHAT THIS IS NOT:
  A solution for an extant lack of productivity in writing papers
# -----------------------------------------------------------------------------------------------
=cut

=pod
# SECTION I
# -----------------------------------------------------------------------------------------------
  DATABASE settings
  for database instance you are connecting to
  required: db_name, $db_user, $db_pass, $db_host
# -----------------------------------------------------------------------------------------------
=cut

@db = ('DBNAME','DBUSER', 'DBPASS', 'DBHOST');


=pod
# SECTION II
# -----------------------------------------------------------------------------------------------
  custom settings
  these functions are very specific for any given study. Using them seems to be the only way of
  having one system that rules them all...
# -----------------------------------------------------------------------------------------------
=cut

# extracts the subject and timepoint identifiers from the patient name
# assumes identifers are stored as <PSCID>_<DCCID>_<visit> in PatientName field, where <visit> is 3 digits.
sub getSubjectIDs {
    my ($patientName, $patientID, $scannerID, $dbhr, $db) = @_;

    my %subjectID; # Will stored subject IDs.

     # If patientName is phantom scan or test scan
     # CandID is scanner DCCID (based on site alias)
     # visitLabel is scan patient name
     # Set createVisitLable to
     #      a. 1 if imaging pipeline should create the visit label (when visit label has not been created yet in the database.
     #      b. 0 if imaging pipeline should not create the visit label (when visit label has not been created yet in the database.
    if ($patientName =~ /PHA/i or $patientName =~ /TEST/i) {

        $subjectID{'CandID'}     = NeuroDB::MRI::my_trim(NeuroDB::MRI::getScannerCandID($scannerID, $db));
        $subjectID{'visitLabel'} = NeuroDB::MRI::my_trim($patientName);
        $subjectID{'isPhantom'} = 1;

        $subjectID{'createVisitLabel'} = 1;

        # When createVisitLabel is set to 1, CohortID must also
        # be set to the ID of the cohort that the newly created
        # visit should have. Assuming for example that all patient
        # names end with "_<myCohortID>", then we could write:
        # ($subjectID{'CohortID'}) = $patientName =~ /_(\d+)$/;
        # When createVisitLabel is set to 0, $subjectID{'CohortID'} is ignored.

        # If config setting 'createVisitLabel' is true
        # then $subjectID{'ProjectID'} must be set to the project ID of the
        # newly created visit. Assuming for example that all patients
        # names that contain the string 'HOSPITAL' are associated to visit
        # done for project with ID 1 and all others to projects with ID 2, we
        # could write:
        # $subjectID{'ProjectID'} = $patientName =~ /HOSPITAL/
        #     ? 1 : 2;
        # When createVisitLabel is set to 0, $subjectID{'ProjectID'} is ignored.

     # If patient match PSCID_DCCID_VisitLabel
     # Determine PSCID, DCCID and visitLabel based on patient name
    } elsif ($patientName =~ /([^_]+)_(\d+)_([^_]+)/) {

        $subjectID{'PSCID'}      = NeuroDB::MRI::my_trim($1);
        $subjectID{'CandID'}     = NeuroDB::MRI::my_trim($2);
        $subjectID{'visitLabel'} = NeuroDB::MRI::my_trim($3);
        $subjectID{'isPhantom'}  = 0;

        $subjectID{'createVisitLabel'} = 0;

        # When createVisitLabel is set to 1, CohortID must also
        # be set to the ID of the cohort that the newly created
        # visit should have. Assuming for example that visits V01 and V02
        # are associated with cohort with ID 1 and all others to cohort
        # with ID 2, then we could write:
        # ($subjectID{'CohortID'}) = $subjectID{'visitLabel'} =~ /^V0[12]$/
        #     ? 1 : 2;
        # When createVisitLabel is set to 0, $subjectID{'CohortID'} is ignored.

        # If config setting 'createVisitLabel' is true
        # then $subjectID{'ProjectID'} must be set to the project ID of the
        # newly created visit. Assuming for example that candidates with a
        # candidate ID greater than 400000 are seen in project 1 and others are
        # seen in project 2, we could write
        # could write:
        # $subjectID{'ProjectID'} = $subjectID{'CandID'} > 400000 ? 1 : 2;
        #     ? 1 : 2;
        # When createVisitLabel is set to 0, $subjectID{'ProjectID'} is ignored.

        print "PSCID is: "            . $subjectID{'PSCID'}      .
                "\n CandID id: "      . $subjectID{'CandID'}     .
                "\n visit_label is: " . $subjectID{'visitLabel'} . "\n";
    }

    # Return subjectIDs
    return \%subjectID;
}

# ----------- OPTIONAL SUBROUTINE
# This function allows the user to decide which images are to be inserted into the database.
# The current default setting is to allow insertion of all the scans
# that meet an mri_protocol table entry to be inserted;
# this is achieved by returning 1 when $acquisitionProtocol ne 'unknown'.
# Alternatively, this routine can be tailored to the user's needs; it can be made to
# insert scans based on exact (eq 't1') or partial regex matching (=~ /despot/), or case
# insensitive partial matching to the scan type (=~ /dti/i), etc...
# as shown in the commented-out line below.
sub isFileToBeRegisteredGivenProtocol {
    my $acquisitionProtocol = shift;
    if($acquisitionProtocol ne 'unknown') {
#    if($acquisitionProtocol eq 't1' or $acquisitionProtocol eq 't2' or $acquisitionProtocol eq 'pd' or $acquisitionProtocol eq 'mrs' or $acquisitionProtocol=~ /dti/i or $acquisitionProtocol =~ /despot/) {
        return 1;
    }
    return 0;
}

# ----------- OPTIONAL SUBROUTINE
# Fetch CandID and Visit info from DTI folder.
sub  get_DTI_CandID_Visit {
    my ($native_dir) =   @_;

    if  ($native_dir =~  /assembly\/(\d\d\d\d\d\d)\/(V\d{1,2})\/mri\//i)  {
        my  $subjID =   $1;
        my  $visit  =   $2;
        return  ($subjID,$visit);
    }else{
        return  undef;
    }
}


=pod

=head3 determineHRRTprotocol($tracer, $ecat_file)

Determines which protocol name to use for the ECAT file (based on the tracer
name, reconstruction algorithm and motion correction used). For the MNI PET
HRRT scanner, the following convention is being used:
- the tracer used is passed to the function as $protocol (which comes from what
was written in the Matlab script accompanying the dataset)
- reconstruction is indicated in the filename by the string DFBP (for FBP
reconstruction) and OSEM (for OSEM reconstruction)
- whether motion correction was applied on the file is indicated by the string _MC01

Note: this will only apply for the HRRT PET scanner from the MNI. Since there is
only 7 of those scanners in the world, we will adapt the scripts if needed when
we will start hosting data from other PET HRRT scanners.

INPUTS:
  - $tracer   : name of the tracer (that was previously parsed from the Matlab
                file accompanying the PET HRRT dataset for the MNI)
  - $ecat_file: name of the ECAT file

RETURNS: the final acquisition protocol to be used when inserting the acquisition
 in the files table.

=cut

sub determineHRRTprotocol {
    my ( $tracer, $ecat_file ) = @_;

    my $protocol = $tracer;
    $protocol =~ s/'|\\|_|"|\s//g; # remove weird characters from protocol name

    if ( $ecat_file =~ /Dfbp/i ) {
        $protocol .= "FBP"; # add FBP reconstruction to filename
    } else {
        $protocol .= "OSEM"; # add OSEM reconstruction to filename
    }

    if ( $ecat_file =~ /_MC01/i ) {
        $protocol .= "mc"; # add mc acronym for motion corrected datasets
    }

    return $protocol;
}


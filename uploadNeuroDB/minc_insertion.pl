determinePSC(\%tarchiveInfo,0);

################################################################
################################################################
####determine the ScannerID ##################################### 
################################################################
################################################################
my $scannerID = $utility->determineScannerID(\%tarchiveInfo,0,$centerID,
                                            $NewScanner
                                           );

################################################################
################################################################
######Construct the $subjectIDsref array########################
################################################################
################################################################
my $subjectIDsref = $utility->determineSubjectID($scannerID,\%tarchiveInfo,0);

################################################################
################################################################
#####Define the $CandMismatchError##############################
################################################################
################################################################
my $CandMismatchError;
my $logQuery = "INSERT INTO MRICandidateErrors".
              "(SeriesUID, TarchiveID,MincFile, PatientName, Reason)".
              " VALUES (?, ?, ?, ?, ?)";
my $candlogSth = $dbh->prepare($logQuery);

if ($subjectIDsref->{'isPhantom'}) {
    # CandID/PSCID errors don't apply to phantoms, so we don't want to trigger
    # the check which aborts the insertion
    $CandMismatchError = undef;
}
   ##if the validation has passed and force is false###
   ###Then the CandMismatchError is null or undef
if (($is_valid) and !($force)){
    $CandMismatchError = undef;
}

################################################################
################Get the SessionID###############################
################################################################
my ($sessionID, $requiresStaging) =
    NeuroDB::MRI::getSessionID( $subjectIDsref, 
                                $tarchiveInfo{'DateAcquired'},
                                \$dbh, $subjectIDsref->{'subprojectID'}
                              );

################################################################
############Construct the notifier object#######################
################################################################
my $notifier = NeuroDB::Notify->new(\$dbh);

################################################################
#### Load/Create create File object#############################
#####And map dicom fields#######################################
################################################################
my $file = $utility->loadAndCreateObjectFile($minc);

################################################################
##optionally do extra filtering, if needed######################
################################################################
if (defined(&Settings::filterParameters)) {
    print LOG " --> using user-defined filterParameters for $minc\n"
    if $verbose;
    Settings::filterParameters(\$file);
}

################################################################
# We already know the PatientName is bad from step 5a, but######
## had to wait until this point so that we have the#############
##SeriesUID and MincFile name compute the md5 hash. Do it#######
## before computing the hash because there's no point in########
##going that far if we already know it's fault.#################
################################################################

if (defined($CandMismatchError)) {
    print LOG "Candidate Mismatch Error is $CandMismatchError\n";
    print LOG " -> WARNING: This candidate was invalid. Logging to
              MRICandidateErrors table with reason $CandMismatchError";
    $candlogSth->execute(
        $file->getParameter('series_instance_uid'),
        $tarchiveInfo{'TarchiveID'},
        $minc,
        $tarchiveInfo{'PatientName'},
        $CandMismatchError
    );
    exit 7 ;  ##replaces next
}

################################################################
##############compute the md5 hash##############################
################################################################
my $unique = $utility->computeMd5Hash($file);
if (!$unique) { 
    print "--> WARNING: This file has already been uploaded! \n"  if $debug;
    print LOG " --> WARNING: This file has already been uploaded!"; 
    exit 8; 
} 

################################################################
###at this point things will appear in the database# ###########
#####Set some file information##################################
################################################################
$file->setParameter('ScannerID', $scannerID);
$file->setFileData('SessionID', $sessionID);
$file->setFileData('SeriesUID', $file->getParameter('series_instance_uid'));
$file->setFileData('EchoTime', $file->getParameter('echo_time'));
$file->setFileData('PendingStaging', $requiresStaging);
$file->setFileData('CoordinateSpace', 'native');
$file->setFileData('OutputType', 'native');
$file->setFileData('FileType', 'mnc');
$file->setFileData('TarchiveSource', $tarchiveInfo{'TarchiveID'});
$file->setFileData('Caveat', 0);

################################################################
##get acquisition protocol (identify the volume)################
################################################################
my ($acquisitionProtocol,$acquisitionProtocolID,@checks)
  = $utility->getAcquisitionProtocol($file,$subjectIDsref,
                                     \%tarchiveInfo,$center_name,
                                     $minc
                                    );

if($acquisitionProtocol =~ /unknown/) {
   print LOG " --> The minc file cannot be registered since the 
              AcquisitionProtocol IS unknown";
   exit 9;
}

################################################################
# Register scans into the database.  Which protocols############
###to keep optionally controlled by the config file#############
################################################################
$utility->registerScanIntoDB(\$file, \%tarchiveInfo,$subjectIDsref, 
                             $acquisitionProtocol, $minc, @checks, 
                             $reckless, $tarchive, $sessionID
                            );

################################################################
### add series notification#####################################
################################################################
$notifier->spool(
    'mri new series', $subjectIDsref->{'CandID'} . " " .
    $subjectIDsref->{'PSCID'} ." " .
    $subjectIDsref->{'visitLabel'} .
    "\tacquired " . $file->getParameter('acquisition_date')
    . "\t" . $file->getParameter('series_description'),
    $centerID
);

print "\nFinished file:  ".$file->getFileDatum('File')." \n" if $debug;


################################################################
##############################succesfully completed#############
################################################################
exit 0;


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



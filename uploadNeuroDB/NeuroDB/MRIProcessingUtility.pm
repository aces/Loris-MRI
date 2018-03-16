package NeuroDB::MRIProcessingUtility;
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

################################################################
#####################Constructor ###############################
################################################################
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

################################################################
## writeErrorLog and update Notification Table##################
## this is a useful function that will close the log and write #
## error messages in case of abnormal program termination ######
################################################################
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


#################################################################    
## useful only if the visit label IS NOT encoded somewhere in ###
## the patient ID or patient Name ###############################
#################################################################    

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

################################################################
########### getFileNamesfromSeriesUID  #########################
################################################################
sub getFileNamesfromSeriesUID {

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

################################################################
##################### extract_tarchive #########################
################################################################
=pod
Most important function now. Gets the tarchive and
extracts it so data can actually be uploaded
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
        exit $NeuroDB::ExitCodes::EXTRACT_ARCHIVE_FAILURE;
    }

    my $dcmtar = $tars[0];
    my $dcmdir = $dcmtar;
    $dcmdir =~ s/\.tar\.gz$//;

    if (defined($seriesuid)) {
        print "seriesuid: $seriesuid\n" if $this->{verbose};
        my @alltarfiles = `cd $this->{TmpDir} ; tar -tzf $dcmtar`;
        $tarnames = getFileNamesfromSeriesUID($seriesuid, @alltarfiles);
        print "tarnames: $tarnames\n" if $this->{verbose};
    }

    `cd $this->{TmpDir} ; tar -xzf $dcmtar $tarnames`;
    return $dcmdir;
}


################################################################
############ sub extractAndParseTarchive #######################
################################################################
sub extractAndParseTarchive {

    my $this = shift;
    my ($tarchive, $tarchive_srcloc, $upload_id, $seriesuid) = @_;

    my $study_dir = $this->{TmpDir}  . "/" .
        $this->extract_tarchive($tarchive, $upload_id, $seriesuid);
    my $ExtractSuffix  = basename($tarchive, ".tar");
    # get rid of the tarchive Prefix 
    $ExtractSuffix =~ s/DCM_(\d){4}-(\d){2}-(\d){2}_//;
    my $info       = "head -n 12 $this->{TmpDir}/${ExtractSuffix}.meta";
    my $header     = `$info`;
    my $message = "\n$header\n";
    $this->{LOG}->print($message);
    $this->spool($message, 'N', $upload_id, $notify_detailed);

    return ($ExtractSuffix, $study_dir, $header);
}

################################################################
################## determineSubjectID ##########################
################################################################
sub determineSubjectID {

    my $this = shift;
    my ($scannerID,$tarchiveInfo,$to_log, $upload_id) = @_;
    $to_log = 1 unless defined $to_log;
    if (!defined(&Settings::getSubjectIDs)) {
        if ($to_log) {
            my $message =  "\nERROR: Profile does not contain getSubjectIDs ".
                           "routine. Upload will exit now.\n\n";
            $this->writeErrorLog(
                $message, $NeuroDB::ExitCodes::GET_SUBJECT_ID_FAILURE
            );
	    $this->spool($message, 'Y', $upload_id, $notify_notsummary);
	    exit $NeuroDB::ExitCodes::GET_SUBJECT_ID_FAILURE;
        }
    }
    my $subjectIDsref = Settings::getSubjectIDs(
                            $tarchiveInfo->{'PatientName'},
                            $tarchiveInfo->{'PatientID'},
                            $scannerID,
                            $this->{dbhr}
                        );
    if ($to_log) {
        my $message = "\n==> Data found for candidate   : ".
                            "CandID: ". $subjectIDsref->{'CandID'} .
                            "- PSCID: ". $subjectIDsref->{'PSCID'} . "- Visit: ".
                            $subjectIDsref->{'visitLabel'} . "- Acquired : ".
                            $tarchiveInfo->{'DateAcquired'} . "\n";
	$this->{LOG}->print($message);
        $this->spool($message, 'N', $upload_id, $notify_detailed);
    }
    return $subjectIDsref;
}


################################################################
################### createTarchiveArray ########################
################################################################

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
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::TARCHIVE_NOT_IN_DB);
	# no $tarchive can be fetched so $upload_id is undef
	# in the notification_spool
        $this->spool($message, 'Y', undef, $notify_notsummary);
        exit $NeuroDB::ExitCodes::TARCHIVE_NOT_IN_DB;
    }

    return %tarchiveInfo;
}

################################################################
#################### determinePSC ##############################
################################################################
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
                $message, $NeuroDB::ExitCodes::GET_PSC_FAILURE
            );
	    $this->spool($message, 'Y', $upload_id, $notify_notsummary);
            exit $NeuroDB::ExitCodes::GET_PSC_FAILURE;
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

################################################################
################## determineScannerID ##########################
################################################################
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
                $message, $NeuroDB::ExitCodes::GET_SCANNERID_FAILURE
            );
       	    $this->spool($message, 'Y', $upload_id, $notify_notsummary);
            exit $NeuroDB::ExitCodes::GET_SCANNERID_FAILURE;
        }
    }
    if ($to_log) {
        $message = "==> scanner ID : $scannerID\n\n";
        $this->{LOG}->print($message);
        $this->spool($message,'N', $upload_id, $notify_detailed);
    }
    return $scannerID;
}

################################################################
####### get_acqusitions($study_dir, \@acquisitions) ############ 
####### puts list of acq dirs in @acquisitions #################
################################################################
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

################################################################
################### compute the md5 hash #######################
################################################################
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

################################################################
#################### getAcquisitionProtocol ####################
################################################################

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

    my @checks = ();
    my $acquisitionProtocolID;
    if ($acquisitionProtocol !~ /unknown/) {
        $acquisitionProtocolID =
        &NeuroDB::MRI::scan_type_text_to_id(
          $acquisitionProtocol, $this->{dbhr}
        );

        if ($bypass_extra_file_checks == 0) {
          @checks = $this->extra_file_checks(
                        $acquisitionProtocolID, 
                        $file, 
                        $subjectIDsref->{'CandID'}, 
                        $subjectIDsref->{'visitLabel'},
                        $tarchiveInfoRef->{'PatientName'}
                    );
          $message = "\nextra_file_checks from table mri_protocol_check " .
                     "logged in table mri_violations_log: $checks[0]\n";
	  $this->{LOG}->print($message);
	  # 'warn' and 'exclude' are errors, while 'pass' is not
	  # log in the notification_spool_table the $Verbose flag accordingly
	  if (!($checks[0] eq 'pass')){
	          $this->spool($message, 'Y', $upload_id, $notify_notsummary);
	  }
	  else{
	          $this->spool($message, 'N', $upload_id, $notify_detailed);
	  }
        }
    }
    return ($acquisitionProtocol, $acquisitionProtocolID, @checks);
}

################################################################
######## extra_file_checks () ##################################
######## Returns list of checks that failed, ###################
######## We can't directly insert here because #################
######## The file isn't registered in the database yet #########
################################################################

sub extra_file_checks() {
      
    my $this = shift;
    my $scan_type = shift;
    my $file = shift;
    my $CandID = shift;
    my $Visit_Label = shift;
    my $PatientName = shift;

    my $query = "SELECT * FROM mri_protocol_checks WHERE Scan_type=?";
    my $log_query = "INSERT INTO mri_violations_log".
                    "(SeriesUID, TarchiveID, MincFile, PatientName,".
                    " CandID, Visit_label, CheckID,  Scan_type,".
                    " Severity, Header, Value, ValidRange,ValidRegex)".
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    if ($this->{debug}) {
        print $query . "\n";
    }
    my $worst_warning = 0;
    my @faillist;
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    my $logsth = ${$this->{'dbhr'}}->prepare($log_query);
    $sth->execute($scan_type);
    while(my $check = $sth->fetchrow_hashref()) {
        my $value = $file->getParameter($check->{'Header'});
        if (($check->{'ValidRange'}
            && (!NeuroDB::MRI::in_range($value, $check->{'ValidRange'})))
            || ($check->{'ValidRegex'} && $value !~ /$check->{'ValidRegex'}/)) 
            {
                if ($check->{'Severity'} =~ /exclude/) {
                    $worst_warning = 2;
                } elsif (
                    $check->{'Severity'} =~ /warning/ 
                    && $worst_warning < 2
                  ) {
                    $worst_warning = 1;
                    $file->setFileData('Caveat', 1);
                }
                $logsth->execute(
                        $file->getFileDatum('SeriesUID'),
                        $file->getFileDatum('TarchiveSource'),
                        $file->getFileDatum('File'),
                        $PatientName,
                        $CandID,
                        $Visit_Label,
                        $check->{'ID'},
                        $check->{'Scan_type'},
                        $check->{'Severity'},
                        $check->{'Header'},
                        $value,
                        $check->{'ValidRange'},
                        $check->{'ValidRegex'}
                );
                push(@faillist, $check->{'ID'});

            }
    }
    if ($worst_warning == 1) {
        return ('warn', \@faillist);
    } elsif ($worst_warning == 2) {
        return ('exclude', \@faillist);
    }
    return ('pass', \@faillist);
}

################################################################
################## update_mri_acquisition_dates ################
################################################################
sub update_mri_acquisition_dates {
   
    my $this = shift;
    my ($sessionID, $acq_date) = @_;

    ############################################################
    # get the registered acquisition date for this session #####
    ############################################################
    my $query = "SELECT s.ID, m.AcquisitionDate FROM session AS s LEFT OUTER".
                " JOIN mri_acquisition_dates AS m ON (s.ID=m.SessionID)". 
                " WHERE s.ID='$sessionID' AND s.Active='Y' AND".
                " (m.AcquisitionDate > '$acq_date'". 
                " OR m.AcquisitionDate IS NULL) AND '$acq_date'>0";
    
    if ($this->{debug}) {
        print $query . "\n";
    }

    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();
    ############################################################
    ### if we found a session, it needs updating or inserting, #
    ### so we use replace into. ################################
    ############################################################
    if ($sth->rows > 0) {
        my $query = "REPLACE INTO mri_acquisition_dates".
                    " SET AcquisitionDate='$acq_date', SessionID='$sessionID'";
        ${$this->{'dbhr'}}->do($query);
    }
}

################################################################
#################### loadAndCreateObjectFile ###################
################################################################

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

################################################################
#################### move_minc #################################
#################### renames and moves $minc ###################
################################################################
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


################################################################
###################### registerScanIntoDB ######################
################################################################
sub registerScanIntoDB {

    my $this = shift;
    my (
        $minc_file, $tarchiveInfo,$subjectIDsref,$acquisitionProtocol, 
        $minc, $checks,$reckless, $sessionID, $upload_id
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
        ) && $checks->[0] !~ /exclude/) {

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
        $tarchive_path =  $tarchiveInfo->{ArchiveLocation};
        $tarchive_path =~ s/$data_dir\///i;
        $${minc_file}->setParameter(
            'tarchiveLocation', 
            $tarchive_path
        );
        $${minc_file}->setParameter(
            'tarchiveMD5', 
            $tarchiveInfo->{'md5sumArchive'}
        );

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
        $this->update_mri_acquisition_dates(
            $sessionID, 
            $tarchiveInfo->{'DateAcquired'}
        );
    }
    return $acquisitionProtocolID;
}

################################################################
################## dicom_to_minc ###############################
################################################################

sub dicom_to_minc {

    my $this = shift;
    my ($study_dir, $converter,$get_dicom_info,
		$exclude,$mail_user, $upload_id) = @_;
    my ($d2m_cmd,$d2m_log,$exit_code);
    my $message = '';
    $d2m_cmd = "find $study_dir -type f | $get_dicom_info -studyuid -series".
               " -echo -image -file -series_descr -attvalue 0018 0024".
               " -stdin | sort -n -k1 -k2 -k6 -k3 -k7 -k4 | grep -iv".
               " $exclude | cut -f 5 | ";
    
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
################################################################
####### get_mincs ##############################################
######## returns a sorted list of mincfiles ####################
################################################################
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
        my $cmd= "Mincinfo_wrapper -quiet -tab -file -date $this->{TmpDir}/$file";
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

################################################################
########################## concat_mri ##########################
################################################################
## concat_mri(\@minc_files, $psc) -> concats & removes #########
## pre-concat mincs ############################################
################################################################
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

################################################################
###################### registerProgs ###########################
################################################################
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

################################################################
############ moveAndUpdateTarchive #############################
################################################################
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

################################################################
###################### CreateMRICandidates #####################
################################################################
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
                $message, $NeuroDB::ExitCodes::CAND_REGISTRATION_FAILURE
            );
            $this->spool($message, 'Y', $upload_id, $notify_notsummary);
            exit $NeuroDB::ExitCodes::CAND_REGISTRATION_FAILURE;
     }
}

################################################################
###############################setMRISession####################
################################################################
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

################################################################
###################### validateArchive #########################
################################################################

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
        $this->writeErrorLog($message, $NeuroDB::ExitCodes::CORRUPTED_TARCHIVE);
        $this->spool($message, 'Y', $upload_id, $notify_notsummary);
        exit $NeuroDB::ExitCodes::CORRUPTED_TARCHIVE;
    }
}

################################################################
############## determines where the mincs will go... ###########
################################################################
sub which_directory {
    my $this = shift;
    my ($subjectIDsref,$data_dir) = @_;
    my %subjectIDs = %$subjectIDsref;
    my $dir = $data_dir;
    $dir = "$dir/assembly/$subjectIDs{'CandID'}/$subjectIDs{'visitLabel'}/mri";
    $dir =~ s/ //;
    return $dir;
}
################################################################
############# validateCandidate ################################
################################################################

sub validateCandidate {
    my $this = shift;
    my ($subjectIDsref)= @_;
    my $CandMismatchError = undef;
    
    ############################################################
    ################## Check if CandID exists ##################
    ############################################################
    my $query = "SELECT CandID, PSCID FROM candidate WHERE CandID=?";
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($subjectIDsref->{'CandID'});
    print "candidate id " . $subjectIDsref->{'CandID'} . "\n" 
	if ($this->{verbose});
    my @CandIDCheck = $sth->fetchrow_array;
    if ($sth->rows == 0) {
        print LOG  "\n\n=> Could not find candidate with CandID =".
                   " $subjectIDsref->{'CandID'} in database";
        $CandMismatchError = 'CandID does not exist';
        return $CandMismatchError;
    }
    
    ############################################################
    ################ Check if PSCID exists #####################
    ############################################################

    $query = "SELECT CandID, PSCID FROM candidate WHERE PSCID=?";
    $sth =  ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($subjectIDsref->{'PSCID'});
    if ($sth->rows == 0) {
        print "\n\n=> No PSCID";
        $CandMismatchError= 'PSCID does not exist';
        return $CandMismatchError;
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
        print "\n\n=> No Visit label";
        $CandMismatchError= 'Visit label does not exist';
        return $CandMismatchError;
    } elsif (($sth->rows == 0) && ($subjectIDsref->{'createVisitLabel'})) {
        print "\n\n=> Will create visit label $subjectIDsref->{'visitLabel'}";
    } 

   return $CandMismatchError;
}

################################################################
#################### computeSNR ################################
################################################################

sub computeSNR {

    my $this = shift;
    my ($row, $filename, $fileID, $base, $fullpath, $cmd, $message, $SNR, $SNR_old);
    my ($tarchiveID, $upload_id, $profile)= @_;
    my $data_dir = NeuroDB::DBI::getConfigSetting(
                        $this->{dbhr},'dataDirBasepath'
                        );

    my $query = "SELECT FileID, file from files f ";
    my $where = "WHERE f.TarchiveSource=?";
    $query = $query . $where;

    if ($this->{debug}) {
        print $query . "\n";
    }

    my $minc_file_arr = ${$this->{'dbhr'}}->prepare($query);
    $minc_file_arr->execute($tarchiveID);

    while ($row = $minc_file_arr->fetchrow_hashref()) {
        $filename = $row->{'file'};
        $fileID = $row->{'FileID'};
        $base = basename($filename);
        $fullpath = $data_dir . "/" . $filename;
        if (defined(&Settings::getSNRModalities)
            && Settings::getSNRModalities($base)) {
                $cmd = "noise_estimate --snr $fullpath";
                $SNR = `$cmd`;
                $SNR =~ s/\n//g;
                print "$cmd \n" if ($this->{verbose});
                print "SNR is: $SNR \n" if ($this->{verbose});
                my $file = NeuroDB::File->new($this->{dbhr});
                $file->loadFile($fileID);
                $SNR_old = $file->getParameter('SNR');
                if ($SNR ne '') {
                    if (($SNR_old ne '') && ($SNR_old ne $SNR)) {
                        $message = "The SNR value will be updated from " .
                            "$SNR_old to $SNR. \n";
                        $this->{LOG}->print($message);
                        $this->spool($message, 'N', $upload_id, $notify_detailed);
                    }
                    $file->setParameter('SNR', $SNR);
                }
        }
        else {
            $message = "The SNR can not be computed for $base. ".
                "Either the getSNRModalities is not defined in your ".
                "$profile file, or the imaging modality is not ".
                "supported by the SNR computation. \n";
            $this->{LOG}->print($message);
            $this->spool($message, 'N', $upload_id, $notify_detailed);
        }
    }
}

################################################################
##########  Order Imaging Modalities By Acquisition ############
################################################################

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

################################################################
################ getUploadIDUsingTarchiveSrcLoc#################
################################################################
=pod
getUploadIDUsingTarchiveSrcLoc()
Description:
  - Get upload_id form the mri_upload table using tarchive SourceLocation

Arguments:
  $tarchive_srcloc: The Tarchive SourceLocation

  Returns: $upload_id : The upload_id from the mri_upload table
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

################################################################
#################spool##########################################
################################################################
=pod
spool()
Description:
   - Calls the Notify->spool function to log all messages

Arguments:
 $this      : Reference to the class
 $message   : Message to be logged in the database
 $error     : if 'Y' it's an error log , 'N' otherwise
 $upload_id: The upload_id
 $verb      : 'N' for few main messages, 'Y' for more messages (developers)
 Returns    : NULL
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


1;

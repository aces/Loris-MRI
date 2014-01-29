package mri_processing_utility;
use English;
use Carp;
use strict;
##use Log::Dispatch;
sub new {
    my $params = shift;
    my ($dbhr,$globArchiveLocation,$debug,@Settings,$TmpDir,$logfile,
	$LogDir,$verbose) = @_;
    unless(defined $dbhr) {
    	croak("Usage: ".$params."->new(\$databaseHandleReference)");
    }

    my $self = {};
    $self->{'dbhr'} = $dbhr;
    $self->{'globArchiveLocation'} = $globArchiveLocation;
    $self->{'debug'} = $debug;
    $self->{'Settings'} = @Settings;
    $self->{'TmpDir'} = $TmpDir;
    $self->{'logfile'} = $logfile;
    $self->{'LogDir'} = $LogDir;
    $self->{'verbose'} = $verbose;

    
   
 

    return bless $self, $params;
}

################################################################
# this is a useful function that will close the log and write###
### error messages in case of abnormal program termination######
################################################################
sub writeErrorLog {
    my ($logfile, $message, $failStatus,$LogDir) = @_;
    print LOG $message;
    print LOG "program exit status: $failStatus";
    `cat $logfile  >> $LogDir/error.log`;
    close LOG;
    `rm -f $logfile `;
}       


#################################################################    
# useful only if the visit label IS NOT encoded somewhere in ####
##the patient ID or patient Name#################################
#################################################################    

sub lookupNextVisitLabel {
    my $this = shift;
    my ($CandID, $dbhr) = @_;
    my $visitLabel = 1;
    my $sth = $${dbhr}->prepare(
        "SELECT Visit_label FROM session WHERE 
         CandID=$CandID ORDER BY ID DESC LIMIT 1"
    );
    $sth->execute();
    if($sth->rows > 0) {
        my @row = $sth->fetchrow_array();
        $visitLabel = $row[0] + 1;
    }
    return $visitLabel;
}
                 

################################################################
#####################extract_tarchive###########################
################################################################
=pod
Most important function now. Gets the tarchive and 
extracts it so data can actually be uploaded
=cut
sub extract_tarchive {
    my $this = shift;
    my ($tarchive, $tempdir) = @_;
    print "Extracting tarchive\n" if ${$this->{'verbose'}};
    `cd $tempdir ; tar -xf $tarchive`;
    opendir TMPDIR, $tempdir;
    my @tars = grep { /\.tar\.gz$/ && -f "$tempdir/$_" } readdir(TMPDIR);
    closedir TMPDIR;
    if(scalar(@tars) != 1) {
        print "Error: Could not find inner tar in $tarchive!\n";
        print @tars . "\n";
        exit(1);
    }
    my $dcmtar = $tars[0];
    my $dcmdir = $dcmtar;
    $dcmdir =~ s/\.tar\.gz$//;

    `cd $tempdir ; tar -xzf $dcmtar`;
    return $dcmdir;
}


################################################################
############sub extractAndParseTarchive#########################
################################################################

sub extractAndParseTarchive{
    
    my $this = shift;
    my ($tarchive) = @_;

    my $study_dir = ${$this->{'TmpDir'}}  . "/" . extract_tarchive($tarchive, ${$this->{'TmpDir'}});
    print "\n studydir: $study_dir \n";
    my $ExtractSuffix  = basename($tarchive, ".tar");
    # get rid of the tarchive Prefix 
    $ExtractSuffix =~ s/DCM_(\d){4}-(\d){2}-(\d){2}_//;
    my $info      = "head -n 12 ${$this->{'TmpDir'}}/${ExtractSuffix}.meta";
    my $header    = `$info`;
    print LOG "\n$header\n";
    return ($ExtractSuffix,$study_dir,$header);
}

################################################################
#####################determinSubjectID##########################
################################################################
sub determinSubjectID {
    
    my $this = shift;
    my ($scannerID,%tarchiveInfo,$to_log) = @_;
    $to_log = 1 unless defined $to_log;

    if (!defined($this->Settings::getSubjectIDs)) {
        if ($to_log) {
            my $message =  "\nERROR: Profile does not contain getSubjectIDs routine.
                         Upload will exit now.\n\n";
            &writeErrorLog(${$this->{'logfile'}}, $message, 66); exit 66;
        }
    }
    my $subjectIDsref = $this->Settings::getSubjectIDs($tarchiveInfo{'PatientName'},
                                            $tarchiveInfo{'PatientID'},
                                            $scannerID,
                                            ${$this->{'dbhr'}});
    if ($to_log) {
        print LOG "\n==> Data found for candidate   : $subjectIDsref->{'CandID'} 
                  - $subjectIDsref->{'PSCID'} - Visit: 
                  $subjectIDsref->{'visitLabel'} - Acquired :
                  $tarchiveInfo{'DateAcquired'}\n";
    }
    return $subjectIDsref;
}

sub createTarchiveArray {
    
    my $this = shift;
    my ($tarchive) = @_;

    my $where = "ArchiveLocation='$tarchive'";
    if (${$this->{'globArchiveLocation'}}) {
        $where = "ArchiveLocation LIKE '%/".basename($tarchive)."'";
    }
    my $query = "SELECT PatientName, PatientID, PatientDoB, md5sumArchive, 
                 DateAcquired, DicomArchiveID, PatientGender, 
                 ScannerManufacturer, ScannerModel, ScannerSerialNumber,
                 ScannerSoftwareVersion, neurodbCenterName, TarchiveID FROM 
                 tarchive WHERE $where";
    print $query . "\n";
    my $sth = ${$this->{'dbhr'}}->prepare($query); $sth->execute();
    my %tarchiveInfo;

    if ($sth->rows > 0) {
        my $tarchiveInfoRef = $sth->fetchrow_hashref();
        %tarchiveInfo = %$tarchiveInfoRef;
    } else {
        my $message = "\n ERROR: Only archived data can be uploaded. This seems
                    not to be a valid archive for this study!\n\n";
        &writeErrorLog(${$this->{'logfile'}} , $message, 77);
        exit 77;
    }
    return %tarchiveInfo;
}


################################################################
########################determinPSC#############################
################################################################

sub determinPSC {

    my $this = shift;
    my (%tarchiveInfo,$to_log) = @_;
    $to_log = 1 unless defined $to_log;
    my ($center_name, $centerID) =
    NeuroDB::MRI::getPSC(
                         $tarchiveInfo{$this->Settings::lookupCenterNameUsing},
                         ${$this->{'dbhr'}}
                        );
    my $psc = $center_name;
    if ($to_log) {
        if (!$psc) {
            print LOG "\nERROR: No center found for this candidate \n\n";
            exit 77;
        }
        print LOG  "\n==> Verifying acquisition center\n -> Center Name  : 
                    $center_name\n -> CenterID     : $centerID\n";
    }
    return ($psc,$center_name, $centerID);
}

################################################################
########################determinScannerID#######################
################################################################
sub determinScannerID {
    
    my $this = shift;
    my (%tarchiveInfo,$to_log,$centerID,$NewScanner) = @_;
    $to_log = 1 unless defined $to_log;
    if ($to_log) {
        print LOG "\n\n==> Trying to determine scanner ID\n";
    }
    my $scannerID = NeuroDB::MRI::findScannerID(
                                         $tarchiveInfo{
                                            'ScannerManufacturer'
                                         },
                                         $tarchiveInfo{'ScannerModel'},
                                         $tarchiveInfo{'ScannerSerialNumber'},
                                         $tarchiveInfo{
                                            'ScannerSoftwareVersion'
                                         },
                                         $centerID,${$this->{'dbhr'}},$NewScanner
                                         );
    if($scannerID == 0) {
        if ($to_log) {
            my $message = "\n ERROR: The ScannerID for this particular scanner does
                         not exist. Enable creating new ScannerIDs in your profile
                         or this archive can not be uploaded.\n\n";
            &writeErrorLog(${$this->{'logfile'}} , $message, 88); exit 88;
            &writeErrorLog(${$this->{'logfile'}} , $message, 88); exit 88;
        }
    }
    if ($to_log)  {
        print LOG "==> scanner ID : $scannerID\n\n";
    }
    return $scannerID;
}

################################################################
####################move_minc###################################
################################################################
=pod
 move_minc(\$minc, \%minc_ids, $minc_type) -> renames and moves $minc

=cut
sub move_minc {
    
    my $this = shift;
    my ($minc, $subjectIDsref, $minc_type, $fileref,$prefix) = @_;

    my ($new_name, $version);
    my %subjectIDs = %$subjectIDsref;

    # figure out where to put the files
    my $dir = which_directory($subjectIDsref);
    `mkdir -p -m 755 $dir/native`;

    # figure out what to call files
    my @exts = split(/\./, basename($$minc));
    shift @exts;
    my $extension = join('.', @exts);

    my $concat = "";
    $concat = '_concat' if $minc =~ /_concat/;

    my $new_dir = "$dir/native";

    $version = 1;
    $new_name = $prefix."_".$subjectIDs{'CandID'}."_".$subjectIDs{'visitLabel'}
                ."_".$minc_type."_".sprintf("%03d",$version).
                $concat.".$extension";
    $new_name =~ s/ //;
    $new_name =~ s/__+/_/g;

    while(-e "$new_dir/$new_name") {
        $version = $version + 1;
        $new_name =  $prefix."_".$subjectIDs{'CandID'}."_".
                     $subjectIDs{'visitLabel'}."_".$minc_type."_".
                     sprintf("%03d",$version).$concat.".$extension";
        $new_name =~ s/ //;
        $new_name =~ s/__+/_/g;
    }

    $new_name = "$new_dir/$new_name";
    my $cmd = "mv $$minc $new_name";
    `$cmd`;
    print LOG "File $$minc \n moved to:\n $new_name\n";
    $$minc = $new_name;
    return $new_name;
}

## get_acqusitions($study_dir, \@acquisitions) -> puts list of
## acq dirs in @acquisitions
sub get_acquisitions {
    
    my $this = shift;
    my ($study_dir, $acquisitions) = @_;
    @$acquisitions = split("\n", `find $study_dir -type d -name \\*.ACQ`);
    print LOG "Acquisitions: ".join("\n", @$acquisitions)."\n";
}


################################################################
#####################compute the md5 hash#######################
################################################################
sub computeMd5Hash {
    
    my $this = shift;
    my ($file) = @_;
    print "file is $file";
    print LOG "==> computing md5 hash for MINC body.\n" if ${$this->{'verbose'}};
    my $md5hash = &NeuroDB::MRI::compute_hash(\$file);
    print LOG " --> md5: $md5hash\n" if ${$this->{'verbose'}};
    $file->setParameter('md5hash', $md5hash);
    my $unique = NeuroDB::MRI::is_unique_hash(\$file);
    return $unique;
}
################################################################
#####################getAcquisitionProtocol#####################
################################################################

sub getAcquisitionProtocol {
   
    my $this = shift;
    my ($center_name, $subjectIDsref,$file, $dbh, $minc,$file,%tarchiveInfo) = @_;

    ####################################################
    ##get acquisition protocol (identify the volume)####
    ####################################################
    print LOG "==> verifying acquisition protocol\n" if ${$this->{'verbose'}};
    my $acquisitionProtocol = &NeuroDB::MRI::identify_scan_db(
                               $center_name, \$subjectIDsref,
                                \$file, \$dbh, $minc
                              );
    print LOG "Acquisition protocol is $acquisitionProtocol\n";
    my @checks = ();
    my $acquisitionProtocolID;
    if($acquisitionProtocol !~ /unknown/) {
        $acquisitionProtocolID =
        &NeuroDB::MRI::scan_type_text_to_id(
        $acquisitionProtocol, \$dbh
        );
     @checks = extra_file_checks($acquisitionProtocolID, $file, 
               $subjectIDsref->{'CandID'}, $subjectIDsref->{'visitLabel'},
               $tarchiveInfo{'PatientName'});
     print LOG "Worst error: $checks[0]\n" if ${$this->{'debug'}};
     return ($acquisitionProtocol,$acquisitionProtocolID,@checks);
    }
}

################################################################
######################### Returns list of checks that failed,### 
#########################we can't directly insert here because##
# the file isn't registered in the database yet#################
################################################################
################################################################

sub extra_file_checks() {
      
    my $this = shift;
    my $scan_type = shift;
    my $file = shift;
    my $CandID = shift;
    my $Visit_Label = shift;
    my $PatientName = shift;

    my $query = "SELECT * FROM mri_protocol_checks WHERE Scan_type=?";
    my $log_query = "INSERT INTO mri_violations_log (SeriesUID, TarchiveID,"
                    ." MincFile, PatientName, CandID, Visit_label, CheckID, "
                    ." Scan_type, Severity, Header, Value, ValidRange, "
                    . "ValidRegex) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    my $worst_warning = 0;
    my @faillist;
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    my $logsth = ${$this->{'dbhr'}}->prepare($log_query);
    $sth->execute($scan_type);
    while(my $check = $sth->fetchrow_hashref()) {
        my $value = $file->getParameter($check->{'Header'});
        if(($check->{'ValidRange'}
            && (!NeuroDB::MRI::in_range($value, $check->{'ValidRange'})))
            || ($check->{'ValidRegex'} && $value !~ /$check->{'ValidRegex'}/)) {
                if($check->{'Severity'} =~ /exclude/) {
                    $worst_warning = 2;
                } elsif($check->{'Severity'} =~ /warning/ && $worst_warning < 2) {
                    $worst_warning = 1;
                    $file->setFileData('Caveat', 1);
                }
                $logsth->execute($file->getFileDatum('SeriesUID'),
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
    if($worst_warning == 1) {
        return ('warn', \@faillist);
    } elsif($worst_warning == 2) {
        return ('exclude', \@faillist);
    }
    return ('pass', \@faillist);
}

################################################################
####################update_mri_acquisition_dates################
################################################################
sub update_mri_acquisition_dates {
   
    my $this = shift;
    my ($sessionID, $acq_date) = @_;

    # get the registered acquisition date for this session
    my $query = "SELECT s.ID, m.AcquisitionDate from session AS s left outer 
                join mri_acquisition_dates AS m on (s.ID=m.SessionID) 
                WHERE s.ID='$sessionID' and (m.AcquisitionDate > '$acq_date' 
                OR m.AcquisitionDate is null) AND '$acq_date'>0";
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();

    # if we found a session, it needs updating or inserting, 
    #so we use replace into.
    if($sth->rows > 0) {
        my $query = "REPLACE INTO mri_acquisition_dates SET AcquisitionDate="
                    ."'$acq_date', SessionID='$sessionID'";
        ${$this->{'dbhr'}}->do($query);
    }
}

################################################################
######################loadAndCreateObjectFile###################
################################################################

sub loadAndCreateObjectFile{

    my $this = shift;
    my ($minc) = @_;

    ############################################################
    ################create File object##########################
    ############################################################
    my $file = NeuroDB::File->new(${$this->{'dbhr'}});

    ############################################################
    ##########load File object##################################
    ############################################################
    print LOG "\n==> Loading file from disk $minc\n" if ${$this->{'verbose'}};
    $file->loadFileFromDisk($minc);
   
    ############################################################
    ############# map dicom fields##############################
    ############################################################
    print LOG " --> mapping DICOM parameter for $minc\n" if ${$this->{'verbose'}};
    NeuroDB::MRI::mapDicomParameters(\$file);
    return $file;
}


################################################################
##############################registerScanIntoDB################
################################################################
sub registerScanIntoDB() {

    my $this = shift;
    my ($acquisitionProtocol,$minc,$file,$data_dir,@checks,$prefix,
    $reckless,%tarchiveInfo,$subjectIDsref,$tarchive,$sessionID) = @_;
        
        ########################################################
        # Register scans into the database.  Which protocols to#
        # keep optionally controlled by the config file.########
        ########################################################
    if ((!defined($this->Settings::isFileToBeRegisteredGivenProtocol)
        || $reckless
        || (defined($this->Settings::isFileToBeRegisteredGivenProtocol)
            && $this->Settings::isFileToBeRegisteredGivenProtocol(
                $acquisitionProtocol)
           )
        )
        && $checks[0] !~ /exclude/) {

        ########################################################
        # convert the textual scan_type into the scan_type id###
        ########################################################
        my $acquisitionProtocolID = &NeuroDB::MRI::scan_type_text_to_id(
                                        $acquisitionProtocol, ${$this->{'dbhr'}}
                                    );
        $file->setFileData('AcquisitionProtocolID', $acquisitionProtocolID);
        print "Acq protocol: $acquisitionProtocol ID: $acquisitionProtocolID\n"
        if ${$this->{'debug'}};

        ########################################################
        # set Date_taken = last modification timestamp########## 
        #(can't seem to get creation timestamp)#################
        ########################################################
        my $Date_taken = (stat($minc))[9];
        # rename and move files
        my $minc_protocol_identified = &move_minc(\$minc, $subjectIDsref,
                                        $acquisitionProtocol, \$file,$prefix
                                       );

        ########################################################
        #####################set the new file_path##############
        ######################################################## 
        my $file_path   =   $minc;
        $file_path      =~  s/$data_dir\///i;
        print "new NAME: ".$minc_protocol_identified ."\n" if ${$this->{'debug'}};
        $file->setFileData('File', $file_path);

        #######################################################
        ###record which tarchive was used to make this file#####
        ########################################################
        my $tarchive_path   =   $tarchive;
        $tarchive_path      =~  s/$data_dir\///i;
        $file->setParameter('tarchiveLocation', $tarchive_path);
        $file->setParameter('tarchiveMD5', $tarchiveInfo{'md5sumArchive'});

        ########################################################
        # register into the db fixme if I ever want a dry run## 
        ########################################################
        print "Registering file into db\n" if ${$this->{'debug'}};
        my $fileID;
        $fileID = &NeuroDB::MRI::register_db(\$file);
        print "FileID: $fileID\n" if ${$this->{'debug'}};

        ########################################################
        ###update mri_acquisition_dates table###################
        ########################################################
        &update_mri_acquisition_dates($sessionID, $tarchiveInfo{'DateAcquired'}
                                      , ${$this->{'dbhr'}}
                                     );
    }
}





################################################################
#######################dicom_to_minc############################
################################################################
=pod
 dicom_to_minc($study_dir) -> converts the dicoms to mincs
 the old version of this was :
 my $d2m_cmd = "find $study_dir -type f | $get_dicom_info -studyuid -series
 -echo -image -file -stdin | sort -n -k1 -k2 -k3 -k4 | cut -f 5 | dcm2mnc 
-dname
 \'\' -stdin -clobber -cmd \"gzip\"  ${$this->{'TmpDir'}} ";
 you can do it either way. I found it to be more useful to exclude scouts
 and localizers since they get discarded anyhow... and there was the Kupio
 problem with localizers having the same series number
 as the subsequent series which would cause the converter to fail or overwrite
=cut
################################################################

sub dicom_to_minc {

    my $this = shift;
    my ($study_dir, $converter,$get_dicom_info,$exclude,$mail_user) = @_;
    # info :   1        2      3      4     5          6          7
    my $d2m_cmd = "find $study_dir -type f | $get_dicom_info -studyuid -series"
                  . " -echo -image -file -series_descr -attvalue 0018 0024"
                  . " -stdin | sort -n -k1 -k2 -k6 -k3 -k7 -k4 | grep -iv"
                  . " $exclude | cut -f 5 | ";
    # use some other converter if specified in the config

    if ($converter ne 'dcm2mnc') {
        $d2m_cmd .= "$converter ${$this->{'TmpDir'}}  -notape -compress -stdin";
    } else {
        $d2m_cmd .= "dcm2mnc -dname '' -stdin -clobber ${$this->{'TmpDir'}} ";
      }
    print "\n" . $d2m_cmd . "\n";
    my $d2m_log = `$d2m_cmd`;

    if($? > 0) {

        my $exit_code = $? >> 8;
        # dicom_to_minc failed...  don't keep going, just email.
        open MAIL, "| mail $mail_user";
        print MAIL "Subject: [URGENT Automated] uploadNeuroDB: 
                    dicom->minc failed\n";
        print MAIL "Exit code $exit_code received from:\n$d2m_cmd\n";
        close MAIL;


        croak("dicom_to_minc failure, exit code $exit_code");

    print "still alive";

   }
    print LOG "### Dicom to MINC:\n$d2m_log";
}
################################################################
##############get_mincs#########################################
################ returns a sorted list of mincfiles#############
################################################################
sub get_mincs {
  
    my $this = shift;
    my ($minc_files) = @_;
    @$minc_files = ();
    opendir TMPDIR, ${$this->{'TmpDir'}} ;
    my @files = readdir TMPDIR;
    closedir TMPDIR;

    my @files_list;
    foreach my $file (@files) {
        next unless $file =~ /\.mnc(\.gz)?$/;
        push @files_list, `Mincinfo -quiet -tab -file -date ${$this->{'TmpDir'}} /$file`;
    }
    open SORTER, "|sort -nk2 | cut -f1 > ${$this->{'TmpDir'}} /sortlist";
    print SORTER join("", @files_list);
    close SORTER;

    open SORTLIST, "<${$this->{'TmpDir'}} /sortlist";
    while(my $line = <SORTLIST>) {
        chomp($line);
        push @$minc_files, $line;
    }
    close SORTLIST;
    `rm -f ${$this->{'TmpDir'}} /sortlist`;
    print LOG "\n### These MINC files have been created: \n".
              join("\n", @$minc_files)."\n";
}

################################################################
##########################concat_mri############################
################################################################
## concat_mri(\@minc_files, $psc) -> concats & removes #########
#####pre-concat mincs###########################################
################################################################
sub concat_mri {
  
    my $this = shift;
    my ($minc_files) = @_;

    # make a list of the mincs to concat (avoid arg list too long errors)
    open CONCATFILES, ">${$this->{'TmpDir'}} /concatfilelist.txt";
    foreach my $file (@$minc_files) {
        print CONCATFILES "$file\n";
    }
    close CONCATFILES;

    mkdir("${$this->{'TmpDir'}} /concat", 0700);

    my $cmd = "cat ${$this->{'TmpDir'}} /concatfilelist.txt | concat_mri.pl -maxslicesep 3.1
               -compress -postfix _concat -targetdir ${$this->{'TmpDir'}} /concat -stdin";
    my $log = `$cmd`;
    `rm -f ${$this->{'TmpDir'}} /concatfilelist.txt`;

    # fixme print LOG "Concat:\n $cmd\n$log\n" if ${$this->{'verbose'}};
    my $concat_count = `\\ls -1 ${$this->{'TmpDir'}} /concat | wc -l`+0;
    if($concat_count > 0) {
        `mv ${$this->{'TmpDir'}} /concat/*.mnc.gz ${$this->{'TmpDir'}} `;
    }
    `rmdir ${$this->{'TmpDir'}} /concat`;
    print LOG "### Count for concatenated MINCs: 
              $concat_count new files created\n";
}



################################################################
########################registerProgs#####################
################################################################
#### There is better ways to do this
# yes.  there is.
sub registerProgs() {
 
    my $this = shift;
    my @toregister = @_;
    foreach my $prog (@toregister) {
        my $present = `which $prog`;
        if (!$present) { die("$prog not found") };
    }
}

################################################################
############moveAndUpdateTarchive###############################
################################################################
sub moveAndUpdateTarchive {

    my $this = shift;
    my ($tarchive_location,%tarchiveInfo) = @_;
    my $query = '';
    print "Moving tarchive into library\n" if ${$this->{'debug'}};
    my $newTarchiveLocation = $this->Settings::tarchiveLibraryDir."/".
    substr($tarchiveInfo{'DateAcquired'}, 0, 4);

    ########################################################
    #####make the directory if it does not yet exist########
    ########################################################
    unless(-e $newTarchiveLocation) {
        mkdir($newTarchiveLocation, 0755);
    }
    ########################################################
    #######determine the new name of the tarchive###########
    ########################################################

    my $newTarchiveFilename = basename($tarchive_location);
    print "newtarchivefilename is $newTarchiveFilename \n";
    $newTarchiveLocation .= "/".$newTarchiveFilename;

    print "new tarchivelocation is $newTarchiveLocation";
    ########################################################
    ######move the tarchive#################################
    ########################################################
    my $mvTarchiveCmd = "mv $tarchive_location $newTarchiveLocation";
    `$mvTarchiveCmd`;

    ########################################################
    # now update tarchive table to store correct location###
    ########################################################
    $query = "UPDATE tarchive SET ArchiveLocation=".
              ${$this->{'dbhr'}}->quote($newTarchiveLocation)." WHERE DicomArchiveID="
             .${$this->{'dbhr'}}->quote($tarchiveInfo{'DicomArchiveID'});
    print $query . "\n"  if ${$this->{'debug'}};

    ${$this->{'dbhr'}}->do("UPDATE tarchive SET ArchiveLocation=".
              ${$this->{'dbhr'}}->quote($newTarchiveLocation)." WHERE DicomArchiveID="
             .${$this->{'dbhr'}}->quote($tarchiveInfo{'DicomArchiveID'})
            );

  return $newTarchiveLocation;
}

################################################################
######################CreateMRICandidates#######################
################################################################
sub CreateMRICandidates {
    # Standardize gender (DICOM uses M/F, DB uses Male/Female)

    my $this = shift;
    my $query = '';
    my ($subjectIDsref,$gender,%tarchiveInfo,$User,$centerID) = @_;

    if ($tarchiveInfo{'PatientGender'} eq 'F') {
            $gender = "Female";
    } elsif ($tarchiveInfo{'PatientGender'} eq 'M') {
        $gender = "Male";
    }

    # Create non-existent candidate if the profile allows for candidate creation
    if (!NeuroDB::MRI::subjectIDExists($subjectIDsref->{'CandID'},${$this->{'dbhr'}})
        && $this->Settings::createCandidates) {
            chomp($User);
            $subjectIDsref->{'CandID'} = NeuroDB::MRI::createNewCandID(${$this->{'dbhr'}});
            $query = "INSERT INTO candidate (CandID, PSCID, DoB, Gender,
                      CenterID, Date_active, Date_registered, UserID,
                      Entity_type) VALUES (" .
            ${$this->{'dbhr'}}->quote(
                $subjectIDsref->{'CandID'}
            ).",".
            ${$this->{'dbhr'}}->quote(
                $subjectIDsref->{'PSCID'}
            ).",".
            ${$this->{'dbhr'}}->quote(
                $tarchiveInfo{'PatientDoB'}
            ) ."," .
            ${$this->{'dbhr'}}->quote($gender).",". ${$this->{'dbhr'}}->quote($centerID). ", NOW(), NOW(),
               '$User', 'Human')";
            ${$this->{'dbhr'}}->do($query);
            print LOG  "\n==> CREATED NEW CANDIDATE :
            $subjectIDsref->{'CandID'}";
    } elsif ($subjectIDsref->{'CandID'}) {# if the candidate exis
        print LOG  "\n==> getSubjectIDs returned this CandID/DCCID :
        $subjectIDsref->{'CandID'}\n";
    } else {
        my $message = "\n ERROR: The candidate could not be considered for 
                    uploading, since s/he is not registered in your database.
                     \n" .
                    " The dicom header PatientID is   : 


        $tarchiveInfo{'PatientID'}\n".
                    " The dicom header PatientName is : 
                    $tarchiveInfo{'PatientName'}\n\n";
        &writeErrorLog(${$this->{'logfile'}} , $message, 66); exit 66;
    }
}

################################################################
###############################setMRISession####################
################################################################
# Most important function now. Gets the tarchive and extracts it so data can
## actually be uploaded
################################################################
sub setMRISession {

    my $this = shift;
    my $query = '';
    my ($subjectIDsref, %tarchiveInfo) = @_;
    # This will actually create a visit count if it is not provided through the
    # IDs in the dicom header
    # The count starts with 1 if there is none.
    if(!defined($subjectIDsref->{'visitLabel'})) {
        $subjectIDsref->{'visitLabel'} =
        lookupNextVisitLabel($$subjectIDsref->{'CandID'}, ${$this->{'dbhr'}});
    }

    # get session ID
    print LOG "\n\n==> Getting session ID\n";
    my ($sessionID, $requiresStaging) =
        NeuroDB::MRI::getSessionID(
            $subjectIDsref, $tarchiveInfo{'DateAcquired'
            }, ${$this->{'dbhr'}}, $subjectIDsref->{'subprojectID'}
        );

    # Retain session ID for tarchive table    
    print LOG "    SessionID: $sessionID\n";    # Staging: $requiresStaging\n";

    # Make sure MRI Scan Done is set to yes, because now there is data.
    if ($sessionID) {
        $query = "UPDATE session SET Scan_done='Y' WHERE ID=$sessionID";
        ${$this->{'dbhr'}}->do($query);
    }
    return ($sessionID, $requiresStaging);
}

################################################################
###############################validateArchive##################
################################################################

sub validateArchive{

    my $this = shift;
    my ($tarchive,%tarchiveInfo) = @_;
      ##my (%tarchiveinfo) = %{$_[0]};
    print LOG  "\n==> verifying dicom archive md5sum (checksum)\n";
    my $md5_check = `md5sum $tarchive`;
    my ($md5_real, $real) = split(' ', $md5_check);
    my ($md5_db  , $db)   = split(' ', $tarchiveInfo{'md5sumArchive'});
    print LOG " -> checksum for target        :  $md5_real\n -> checksum 
                from database     :  $md5_db\n";

    if ($md5_real ne $md5_db) {
        my $message =  "\nerror: archive seems to be corrupted or modified. upload
                     will exit now.\nplease read the creation logs for more
                     information!\n\n";
        &writeErrorLog(${$this->{'logfile'}} , $message, 77); exit 77;
    }
}




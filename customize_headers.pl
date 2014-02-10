#!/usr/bin/perl
use strict;
use Carp;
use Getopt::Tabular;
use Data::Dumper;
use FindBin;
# These are the NeuroDB modules to be used
use lib "$FindBin::Bin";
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::DBI;
use NeuroDB::Notify;
use DICOM::DCMSUM;
use File::Basename;
###########################################################################
#######################INITIALIZATION######################################
###########################################################################
my $mri_location = "/data/incoming/gusto";
my $mri_processed_location = "/data/incoming/gusto_processed";
my $tarchive_location = "/data/gusto/data/tarchive/";
my $DICOMTAR = "/data/gusto/bin/mri/dicom-archive/dicomTar.pl";
my $update_header = "/data/gusto/bin/mri/dicom-archive/updateHeaders.pl"; 
my $profile = "prod";
my $finalTarget;
my $log = "/data/gusto/data/logs/Dicoms_not_inserted_" . `date +'%d%m%y'`;
my $log2 = "/data/gusto/data/logs/Dicoms_not_updated_" . `date +'%d%m%y'`;
my $UID_track_log = '/data/gusto/bin/mri/UID_issues_list_' . `date +'%d%m%y'`;
my $patient_id = "GUSTO";
###########################################################################
################Load the profile environement##############################
###########################################################################
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if ($profile && !defined @Settings::db) { 
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n"; exit 33; 
}

###########################################################################
######################connect to the database##############################
###########################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "connected";
###########################################################################
##################Open the file to log the tarchives###########################
###########################################################################
open (MYFILE, '>/data/gusto/data/logs/tarchive_files.txt');
open (MY_PATIENT_LOG, '>/data/gusto/data/logs/tarchive_patient_log.txt');

open (MYLOG, ">>$log");
open (MYLOG2, ">>$log2");

###########################################################################
##############################Remove the temporary files##################
###########################################################################
my $cmd = "rm -rf /tmp/*";
system($cmd);

###########################################################################
##################Running the scripts######################################
#################if no argument run it for all the existing folders########
###########################################################################
my $file = $ARGV[0] ;
my $the_file;

###########################################################################
#########Execute DICOM tar and update headers for each file...#############
###########################################################################
if (!($file eq '')){
   ##open (FILE, $file); 
   ## while (<FILE>) {
   ##    chomp;
   ##   s/\s*$//;
   ##  s/\s+$//;
   Execute($file);
} else {
    my @files = <$mri_location/*>;
    foreach $file (@files) {
    	    print "=================begin===============================================\n";
		    Execute($file);
   		    print "=================end===============================================\n";
    }
}
close (MYFILE);
close (MYLOG);
close (MYLOG2);

##########################################################################
#######executes the dicomtar and updateheaders for the given file...
##############################################################################
sub Execute {


######################################################################################
#####################SET THE PATIENT NAME#############################################
######################################################################################
#######file path############
    my $file_path = shift;
    print "file path is $file_path \n"    ;
	chomp $file_path;
    my ($file_target,$visit_label,$candid,$pscid_from_folder,$patient_name,$archive_location,$cmd,
        $result,$file_name,$folder_name)='';

    #####Check to see if the file is of type tgz before untarring it############
    ##$foldername = dirname($file_path)##folder name
    ##$basename = basename($file_path);
    ##find  $foldername -name $basename  -exec /bin/tar -xzvf {} \; -exec rm {} \;
    ##tar -cvzf $file_path


#####Get the file-name######
	my @temp_files = split(/\//,$file_path);
    $file_target = $temp_files[4];

######Get visit_label#########
    my @splitted = split (/-/,$file_target);
    ###print "splitted is " . $splitted[1] . "\n";  04123_Neonatal
    my ($family_id,$second,$third)= split(/_/,($splitted[1]));
    $pscid_from_folder = lookupPSCID($family_id,\$dbh);

########GET the canid from the pscid####
	$candid = NeuroDB::MRI::lookupCandIDFromPSCID($pscid_from_folder,\$dbh);
	if (!$candid ) {
        print "\n ERROR No candidate id  found for the pscid : $pscid_from_folder \n";
	}
######Get visit_label###################
    $visit_label = getVisitLabel($second.$third);
#######patient-name###############/getVisitLabel######
    $patient_name = $pscid_from_folder . "_" . $candid . "_" . $visit_label;
     ##insert it into the log file if the patientname already exists
     if (PatientNameExists($patient_name,\$dbh)){
        print "patientname $patient_name already exist in the database for $file_target \n";
        print MYLOG "patientname $patient_name already exist in the database for $file_target \n";
     }
#####################################################################################
####run dicomtar or updateheaders only if the finaltargetlocation doesn't exists.....
####meaninng the file is not inserted...##############################################
######################################################################################
    $archive_location = getArchiveLocation($file_target);
	if (getArchiveLocation($file_target) eq '') {
       
#####################################################################################
###############create the archive files##############################################
######################################################################################
        $cmd = "$DICOMTAR $file_path $tarchive_location -mri_upload_update -clobber -database -profile $profile ";
        print $cmd . "\n";
        system($cmd);

######################################################################################
#######update the headers (Patient ID and Patient_Name)###############################
#####################################################################################
        $finalTarget= getArchiveLocation($file_target);

#####################################################################################
##The dicom must be inserted into the tarchive table for it to ######################
#####be updated######################################################################
#####################################################################################
	    if (!($finalTarget eq '')) {
            $cmd = "$update_header $finalTarget -verbose -set '(0010,0010)' $patient_name -database  -profile prod";
   		    print $cmd . "\n";
  		    system ($cmd);
   	      	$cmd = "$update_header $finalTarget  -verbose -set '(0010,0020)' $patient_id -database  -profile prod";
    		print $cmd . "\n";
	    	$result = `$cmd`;
####################################################################################
#######################if updated or not############################################
########################write the results into a file###############################
####################################################################################
  	        if (isDicomUpdated($file_target) eq '') {
		        print MYLOG2 "$file_target is not updated in the tarchive table..\n";
     		}
            $file_name = basename($finalTarget) ;
	    	print MYFILE "$file_name \n";
	    	print MY_PATIENT_LOG "$patient_name \n";
####################################################################################
########################Move the mri-file to the mri_processed location#############
#################################################################################### 					
            $cmd = "mv  $file_path $mri_processed_location";
            print $cmd . "\n";
            system($cmd);

	    } else {
	          print MYLOG "$file_target is not added to the tarchive table..\n";
  	      }
    } else {
	    print $file . "is not processed\n";
    }
}	 


#######################################################################################
#####################are the dicom files updated######################################
#######################################################################################
sub isDicomUpdated {
    my $patientID = ''; 
	my $file = shift;
	my $query = "SELECT PatientID FROM tarchive WHERE ArchiveLocation LIKE '\%$file\%'";
 	my $sth = $dbh->prepare($query);
 	$sth->execute();
	if ($sth->rows > 0) {
  	    my @row = $sth->fetchrow_array();
  		$patientID = $row[0];
	}
	return $patientID;
}


#######################################################################################
##########################get the archive target_name##################################
#######################################################################################
sub getArchiveLocation {

    my $f = shift;

	chomp $f;
	my $finalTarget;
	my $query = "SELECT ArchiveLocation FROM tarchive WHERE SourceLocation LIKE '\%$f\%'";
	my @temp = ();
 	my $sth = $dbh->prepare($query); 
	$sth->execute();
	if ($sth->rows > 0) {
	    $finalTarget = $sth->fetchrow_array();
	} 
	return $finalTarget;
}


#####################################################################################
###extracts the raw PSCID from the dicom file....
#####################################################################################
sub ExtractPSCIDFromFile {
    my $file_path  = shift;
    #my $file_to_extract_pn = $file_path . "/dicom/pa1/st1/se1/im1";
    my $file_to_extract_pn = GetFilePath ($file_path,"IM1");
    chomp($file_to_extract_pn);
    print 'file_to_extract_pn : ' . $file_to_extract_pn . "\n";
    my $cmd = "dcmdump --search '0010,0010' '$file_to_extract_pn'";
    print $cmd . "\n";
    my $value = `$cmd`;
    return $value;
}


#####################################################################################
##issue: sometimes the structure of the id in the file is 010-4137 which refers to 020-04137
##--these exceptions must be taken into account..
###parse the extracted the PSCID from the dicom file....
#####################################################################################
sub ParseExtractedPSCIDFromFile {
    $_ = shift;
    if(/(\d+)\s?-\s?(\d+)\s?-?\s?(\d*)/){
    #if (/(\d+)-(\d+)-?(\d*)/){
       return $1 . "0" . "-" . $2;
    }
    return '';
}

############################################################################################
#####converts the visit_label extracted from the filename to the visitlabel used in the db####
#############################################################################################
sub getVisitLabel{
  my $mri_visit_label= shift;
  my $visit_label;
  if (index($mri_visit_label, '6mth') !=-1) {
      $visit_label = '6month';
  }
  if (index($mri_visit_label,'6wk')!=-1) {
      $visit_label = '6week_mri';
  }
  if (index($mri_visit_label, 'Neonatal') !=-1) {
      $visit_label = 'MRIday';
  }

  my $query = "SELECT visit_label FROM visitlabel_mri_rel WHERE visit_label_mri LIKE '%$visit_label%'";
  my $sth = $dbh->prepare($query);
  $sth->execute();
  if($sth->rows > 0) {
      my @row = $sth->fetchrow_array();
      if ($row[0] ne ""){
         $visit_label = $row[0];
      }
  }
  return $visit_label;
}
#####################################################################################
####get visitdate from Database############
#####################################################################################
sub getVisitdateFromDB{
	my ($pscid,$visit_label,$dbhr) = @_;
	my $instrument;
        my $date_taken;
	if ($visit_label eq ''){ 
	    $visit_label = 'MRIday';
	 }
	if ($pscid ne '') {
	    my $query = "select b.Date_taken from baby_crf2 b, session s, flag f where b.CommentID = f.CommentID and f.SessionID = s.ID and s.pscid = '$pscid' and s.Visit_label = '$visit_label' and f.commentID not like '%DDE%'";
            #print $query ."\n";
	    my $sth = $${dbhr}->prepare($query);
            $sth->execute();
            if($sth->rows > 0) {
		my @row = $sth->fetchrow_array();
	        $date_taken = $row[0];
	     }
	    ##remove the '-' from the date..
	    if ($date_taken=~ /-/){
	    	$date_taken =~ s/-//g;
	    } 
	    ##print "date taken" . $date_taken . "\n";
            return $date_taken
        }
}
#####################################################################################
##Get the acquisition date from the file...
##usese the file-path
#####################################################################################
sub getAcquisitionDateFromFile{
    my $file_path = shift;
    my $file_to_extract_pn = GetFilePath ($file_path,"IM1");
    my $cmd = "dcmdump --search 'AcquisitionDate' '$file_to_extract_pn'";
    print $cmd . "\n";
    my $value = `$cmd`;
    my @splitted = split (/ /, $value);
    return substr($splitted[2],1,length($splitted[2])-2);
}
#####################################################################################
####series-description from file#####
#####################################################################################
sub getSeriesDescriptionFromFile{
    my $file_path = shift;
    my $file_to_extract_pn = GetFilePath ($file_path,"IM1");
    my $cmd = "dcmdump --search 'SeriesDescription' '$file_to_extract_pn'";
    print $cmd . "\n";
    my $string = `$cmd`;
    my @splitted = split (/\[/, $string);
    my @splitted = split (/\]/, $splitted[1]);
    return $splitted[0];     
}
#####################################################################################
##get a random file from the directory...
#####################################################################################
sub GetFilePath{
   
    my ($file_path,$file) = @_;
    my $cmd = "find $file_path -name '*$file*' \| head -1";
    print $cmd . "\n";
    my $file= `$cmd`;
    chomp ($file);
   
    return $file;
}


#####################################################################################
##ooks up the PSCID from the database given the family id
#####################################################################################

=pod
B<lookupPSCID( C<$pscid> )>
Looks up the PSCID from the database given the family id
Returns: the PSCID or 0 if the PSCID does not exist
=cut
sub lookupPSCID {
    my ($family_id, $dbhr) = @_;
    my $pscid = 0;
    my $query = "SELECT PSCID FROM candidate WHERE PSCID like '\%$family_id\%'";
    print "\n query is $query \n";
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();
    if($sth->rows > 0) {
        my @row = $sth->fetchrow_array();
        $pscid = $row[0];
    }
    return  $pscid;
}


=pod
B<lookupCandIDFromPSCID( C<$pscid> )>
Looks up the CandID for a given PSCID
Returns: the CandID or 0 if the PSCID does not exist
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

sub PatientNameExists{
    my ($pname,$dbhr) = @_;
    
    my $sth = $${dbhr}->prepare("SELECT * FROM tarchive WHERE PatientName=".$${dbhr}->quote($pname));
    $sth->execute();
    if($sth->rows > 0) {
      return 1;
    }
   return 0;

}






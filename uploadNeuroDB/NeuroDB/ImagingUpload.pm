package NeuroDB::ImagingUpload;
use English;
use Carp;
use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use Path::Class;
use File::Find;
use NeuroDB::FileDecompress;
use File::Temp qw/ tempdir /;

=pod
todo:


1) Create an  actuall function that sources the file
http://stackoverflow.com/questions/6829179/how-to-source-a-shell-script-environment-variables-in-perl-script-without-fork
=cut
################################################################
#####################Constructor ###############################
################################################################
###The constructor needs the location of the uploaded file
###which will be in a temp folder i.e /tmp folder
###once the validation passes the File will be moved to a
### final destination directory
################################################################
sub new {
    my $params = shift;
    my ($dbhr,$uploaded_temp_folder,$pname) = @_;
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
    $self->{'uploaded_temp_folder'} = $uploaded_temp_folder;
    $self->{'dbhr'} = $dbhr ;
    $self->{'pname'} = $pname ;
    return bless $self, $params;
}



#################################################################
##############################setEnvironment#####################
#################################################################
sub setEnvironment {
  my $this = shift;
  my $environment_file = $Settings::data_dir . "/" . "environment";
  my $command = "source $environment_file";
  $this->runCommand($command);

}
#################################################################
#####################IsValid#####################################
#################################################################
###Validates the File to be uploaded#############################
####if the validation passes the following will happen:
####1) Copy the file from tmp folder to the /data/incoming
####2) Set the isvalidated to true in the mri_upload table

#################################################################

sub IsValid  {
    my $this = shift;
    my $message = '';
    ##my $file_decompress = FileDecompress->new(
	##		$this->{'uploaded_temp_folder'}
    ##                 );
    #################################################
    ####Get a list of files from the folder
    #################################################
    print "folderrrr". $this->{'uploaded_temp_folder'} ;
    my $files_not_dicom = 0;
    my $files_with_unmatched_patient_name = 0;
    my $is_valid = 0;     
    #################################################
    #############Loop through the files##############
    #################################################
    my @file_list;
    find ( sub {
    	return unless -f;       #Must be a file
	push @file_list, $File::Find::name;
    }, $this->{'uploaded_temp_folder'} );

    foreach(@file_list) {
	    ############################################################
	    ###  1) Check to see if it's dicom##########################
	    ###  2) Check to see if the header matches the patient-name#
	    ############################################################
            if (($_ ne '.') && ($_ ne '..'))  {
      	          if (!$this->isDicom($_)) {
            		$files_not_dicom++;
	          }
         	  if (!$this->PatientNameMatch($_)) {
                   
         	    $files_with_unmatched_patient_name++;
                  }
            }
    }

   if ($files_not_dicom > 0)  {
       $message = "\n ERROR: there are $files_not_dicom files which are " .
                   "Are not DiCOM";
       print ($message);
       return 0;

   }
   if ($files_with_unmatched_patient_name>0) {
        $message = "\n ERROR: there are $files_with_unmatched_patient_name files".
                   " where the patient-name doesn't match ";
     print ($message);
     return 0;
   }
   return 1; ##return true
}


#################################################################
###############################runDicomTar#######################
#################################################################
sub runDicomTar {
    my $this = shift;
    my $tarchive_id ='';
    my $query = '';
    my $where = '';
    my $tarchive_location = $Settings::data_dir. "/" . "tarchive";
    my $dicomtar = $Settings::bin_dir. "/". "dicom-archive" . "/". "dicomTar.pl";
    my $command = "perl $dicomtar " . $this->{'uploaded_temp_folder'} .   
	" $tarchive_location -clobber -database -profile prod";
    my $output = $this->runCommandWithExitCode($command);
    if ($output==0) {

        
      ########################################################
      ##########Extract tarchiveID using pname################
      ########################################################

        $query = "SELECT TarchiveID FROM tarchive ".
        " WHERE PatientName =?";

        my $sth = ${$this->{'dbhr'}}->prepare($query);
        $sth->execute($this->{'pname'});
        if ($sth->rows> 0) {
            $tarchive_id = $sth->fetchrow_array();
        }

      ########################################################
      #################Update MRI_upload Table accordingly####
      ########################################################
        $where = "WHERE PatientName=?";
        $query = "UPDATE mri_upload SET TarchiveID='$tarchive_id'";
        $query = $query . $where;
        my $mri_upload_update = ${$this->{'dbhr'}}->prepare($query);
        $mri_upload_update->execute($this->{'pname'});
        return 1;   

    }
    return 0;
}


################################################################
###################getTarchiveFileLocation######################
################################################################
sub getTarchiveFileLocation {
    my $this = shift;
    my $archive_location  = '';
    print "\n". $this->{'uploaded_temp_folder'} . "\n";
    my $query = "SELECT t.ArchiveLocation FROM tarchive t ".
      " WHERE t.SourceLocation =?";
      print "\n" . $query . "\n";
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($this->{'uploaded_temp_folder'});
    if ($sth->rows> 0) {
        $archive_location = $sth->fetchrow_array();
    }
    return $archive_location;
}

##################################################################
###############################runInsertingScripts################
##################################################################
sub runInsertionScripts {
  my $this = shift;
  my $archived_file_path = $this->getTarchiveFileLocation();
  my $command = $Settings::bin_dir. 
    "/uploadNeuroDB/tarchiveLoader" . 
	" -globLocation -profile prod $archived_file_path";
  print "\n" . $command . "\n";
  my $output = $this->runCommandWithExitCode($command);
  return $output;
}

#################################################################
###############################getgetArchivedFiles###############
#################################################################
sub getArchivedFiles {
  my $this = shift;
  my $files = ${$this->{'extract_object'}}->files;
  return $files;
}
#################################################################
###############################getType###########################
#################################################################

sub getType {
  my $this = shift;
  my $type = ${$this->{'extract_object'}}->type;
  return $type;
}
#################################################################
###############################PatientNameMatch##################
#################################################################
sub PatientNameMatch {
 my $this = shift;
 my ($dicom_file) = @_;
 my $cmd = "dcmdump $dicom_file | grep PatientName";

 my $patient_name_string = $this->runCommand($cmd);
 if (!($patient_name_string)) {
   print "the patientname cannot be extracted";
   exit 1;
 }
 ##print "\n \n $patient_name_string  \n \n";
 my ($l,$pname,$t) = split /\[(.*?)\]/, $patient_name_string;
 if ($pname ne  $this->{'pname'}) {
    my $message = "The patient-name $pname does not Match" .
          $this->{'pname'};
    print $message;
    return 0; ##return false
 }
 return 1; ##return true

}
################################################################
###############################If DICOM File####################
################################################################
sub isDicom {
 my $this = shift;
 my ($dicom_file) = @_;
 ##print "\n \n dicom_file is ". $dicom_file . "\n";
 my $file_type = $this->runCommand("file $dicom_file") ;
 if (!($file_type =~/DICOM/)) {
    print "not of type DICOM";
    return 0;
 }
 return 1;
}


################################################################
###################getTarchiveFileLocation######################
################################################################
sub getTarchiveFileLocation {
	my $this = shift;
	my $archive_location  = '';
    print "\n". $this->{'uploaded_temp_folder'} . "\n";
	my $query = "SELECT t.ArchiveLocation FROM tarchive t ".
	  " WHERE t.SourceLocation =?";
      print "\n" . $query . "\n";
	my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($this->{'uploaded_temp_folder'});
	if ($sth->rows> 0) {
		$archive_location = $sth->fetchrow_array();
	}
	return $archive_location; 
}
################################################################
###############################moveUploadedFile#################
################################################################
sub moveUploadedFile {
    my $this = shift;
    my $incoming_folder = $Settings::IncomingDir;
    my $cmd = "cp -R " . $this->{'uploaded_temp_folder'} . " " . $incoming_folder ;
    $this->runCommand($cmd);
}

################################################################
###############################runCommandWithExitCode###########
################################################################

sub runCommandWithExitCode {
    my $this = shift;
    my ($query) = @_;
    print "\n\n $query \n\n ";
    my $output =  system($query);
    return  $output >> 8; ##returns the exit code
}

################################################################
###############################runCommand#######################
################################################################

sub runCommand {
    my $this = shift;
    my ($query) = @_;
    print "\n\n $query \n\n ";
    return `$query`;
}




1; 

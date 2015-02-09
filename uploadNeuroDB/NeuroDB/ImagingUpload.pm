package NeuroDB::ImagingUpload;
use English;
use Carp;
use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use Path::Class;
use FileDecompress;
use File::Temp qw/ tempdir /;

=pod
todo:

    ----  is valid function 
    ----  dicomtar function...
    ----- tarchiveLoader function
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
    my ($dbhr,$temp_file_path,$pname) = @_;
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
    $self->{'temp_file_path'} = $temp_file_path;
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
    my $file_decompress = FileDecompress->new(
			$this->{'temp_file_path'}
                     );
    #################################################
    ####Get a list of files from the archive
    #################################################
    my @files = $file_decompress->getArchivedFiles();	
    my $files_not_dicom = 0;
    my $files_with_unmatched_patient_name = 0;
    my $is_valid = 0;     
    #################################################
    #############Loop through the files##############
    #################################################
    foreach (@files) {

    ############################################################
    ###  1) Check to see if it's dicom##########################
    ###  2) Check to see if the header matches the patient-name#
    ############################################################
    
    	if (!isDicom($_)) {
    		$files_not_dicom++;
        }
        if (!PatientNameMatch($_)) {
 		    $files_with_unmatched_patient_name++;
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
    my $tarchive_location = $Settings::data_dir. "/" . "tarchive";
    my $dicomtar = $Settings::bin_dir. "/". "dicom-archive" . "/". "dicomTar.pl";
    my $command = "perl $dicomtar" . $this->{'temp_file_path'} .   
	"$tarchive_location -clobber -database -profile prod";
    my $output = $this->runCommand($command);
    $output = $output >> 8; ##returns the exit code
    return $output;
}

##################################################################
###############################runInsertingScripts################
##################################################################
sub runInsertionScripts {
  my $this = shift;
  my $archived_file_path = $this->getTarchiveFileLocation();
  my $command = $Settings::bin_dir. "/uploadNeuroDB/tarchiveLoader" . 
		"-globLocation -profile prod $archived_file_path";
  my $output = $this->runCommand($command);
  $output = $output >> 8; ##returns the exit code
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
 my $cmd = "dcmdump $dicom_file | grep -i patientname";

 my $patient_name_string = $this->runCommand($cmd);
 my ($l,$pname,$t) = split /^\[(.*?)\]^/, $patient_name_string;
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
 my $file_type = $this->runCommand("file $dicom_file") ;
 if ($file_type =~/DICOM/) {
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
	my $query = "SELECT t.ArchiveLocation FROM mri_upload m 
	   JOIN t tarchive ON (m.TarchiveID = t.TarchiveID)
	   WHERE m.SourceLocation =?";
	my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($this->{'temp_file_path'});
	if ($sth->rows> 0) {
		$archive_location = $sth->fetchrow_array();
	}
	return $archive_location; 
}
################################################################
###############################moveUploadedFile#################
################################################################
sub moveUploadedFile {
}

################################################################
###############################runCommand#######################
################################################################

sub runCommand {
 my $this = shift;
 my ($query) = @_;
 return `$query`;
}


0; 

package NeuroDB::ImagingUpload;
use English;
use Carp;
use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use Path::Class;
use NeuroDB::FileDecompress;
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


####Todo##
=pod
--this needs to be tested...It may not work...

=cut 



###############################################################################
##############################getgetArchivedFiles##############################
###############################################################################

sub setEnvironment {
  my $environment_file = $Settings::data_dir . "/" . "environment";
  $environment_set = $this->runCommand("source $environment_file");

}
################################################################
#####################IsValid##################################
################################################################
###Validates the File to be uploaded############################
####if the validation passes the following will happen:
####1) Copy the file from tmp folder to the /data/incoming
####2) Set the isvalidated to true in the mri_upload table

################################################################

sub IsValid  {
    my $this = shift;
    my $file_decompress = NeuroDB::FileDecompress->new(
			$this->{'temp_file_path'}
                     );
    ####Get a list of files from the archive
    my @files = $file_decompress->getArchivedFiles();	
    my $files_not_dicom = 0;
    my $files_with_unmatched_patient_name = 0;
     
    #############Loop through the files##############
    foreach (@files) {
=pod
          1) Check to see if it's dicom
          2) Check to see if the header matches the patient-name            
=cut    
    	if (!isDicom($_)) {
		$files_not_dicom++;
        }
        if (!PatientNameMatch($_)) {
 		$files_with_unmatched_patient_name++;
	}
    }

   if (($files_not_dicom > 0) || 
      ($files_with_unmatched_patient_name>0)) 
	return 0;
   return  1;
}


###############################################################################
###############################runDicomTar#####################################
###############################################################################
sub runDicomTar {
  my $this = shift;
  my $data_dir = $Settings::data_dir;
=pod
1) run the dicomtar
2) get the tarchiveid
3) update the mri-upload table with the specific info (i.e archiveid if the file is created and tarchive id is not null)
   - 

=cut
  # $cmd = "perl $DICOMTAR $decompressed_folder $tarchive_location -clobber -database -profile prod";
  
=pod
      $db->update(
                "mri_upload",
                array('TarchiveID' => $tarchive_id),
                array('SourceLocation' => $source_location)
            );
            $this->tpl_data['dicom_success'] = true;
            $data = array(
                     $tarchive_id,
                     $ArchiveLocation,
                    );
            return $data;
=cut
  ##run dicomtar.pl
}

###############################################################################
###############################runDicomTar#####################################
###############################################################################
sub runDicomTar {
  my $this = shift;
  my $data_dir = $Settings::data_dir;
  ##run dicomtar.pl
}



###############################################################################
###############################getgetArchivedFiles#############################
###############################################################################


sub getArchivedFiles {
  my $this = shift;
  my $files = ${$this->{'extract_object'}}->files;
  return $files;
}

###############################################################################
###############################getType#########################################
###############################################################################

sub getType {
  my $this = shift;
  my $type = ${$this->{'extract_object'}}->type;
  return $type;
}
##################################################################################
###############################PatientNameMatch###################################
##################################################################################

sub PatientNameMatch {
 my $this = shift;
 my ($dicom_file) = @_;

 $cmd = "dcmdump $file | grep -i patientname";

 $patient_name_string = $this->runCommand($cmd);
 my ($l,$pname,$t) = split /^\[(.*?)\]^/, $patient_name_string;
 if ($pname eq  $this->{'pname'})
   return 1;
 return 0;
}
##################################################################################
###############################If DICOM File######################################
##################################################################################
sub isDicom {
 my $this = shift;
 my ($dicom_file) = @_;
 $file_type = $this->runCommand("file $dicom_file") ;
 if ($file_type =~/DICOM/) return 1;
 return 0;
}


sub moveUploadedFile {
}

sub runCommand {
 my $this = shift;
 my ($query) = @_;
 return `$query`;
}

sub runBatchUpload {
##$command = "cd $mri_code_path; perl $batch_upload_script< $tarchive_file_log";
 

}

1; 

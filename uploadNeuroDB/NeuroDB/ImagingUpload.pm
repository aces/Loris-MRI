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
    my ($dbhr,$uploaded_temp_folder,$upload_id,$pname,$profile) = @_;
    unless(defined $dbhr) {
        croak(
                "Usage: ".$params."->new(\$databaseHandleReference)"
             );
    }
    my $self = {};

    ############################################################
    ############### Create a settings package ##################
    ############################################################
    {
        package Settings;
        do "$ENV{LORIS_CONFIG}/.loris_mri/$profile";
    }

    ############################################################
    ############### Create a Log Object ########################
    ############################################################

    my $Log = NeuroDB::Log->new($dbhr,'ImagingUpload',$upload_id,$profile);
    $self->{'Log'} = $Log;

    $self->{'uploaded_temp_folder'} = $uploaded_temp_folder;
    $self->{'dbhr'} = $dbhr ;
    $self->{'pname'} = $pname ;
    $self->{'upload_id'} = $upload_id ;
    return bless $self, $params;
}

#################################################################
#####################IsValid#####################################
#################################################################
###Validates the File to be uploaded#############################
####if the validation passes the following will happen:
####1) Copy the file from tmp folder to the /data/incoming
####2) Set the isvalidated to true in the mri_upload table

#################################################################
##TODO
##Put these in the log table
#############
sub IsValid  {
    my $this = shift;
    my ($message,$query,$where) = '';
    ##my $file_decompress = FileDecompress->new(
    ##		$this->{'uploaded_temp_folder'}
    ##                 );
    #################################################
    ####Get a list of files from the folder
    #################################################
    my $files_not_dicom = 0;
    my $files_with_unmatched_patient_name = 0;
    my $is_valid = 0;    
    my @row = (); 
    #################################################
    #############Loop through the files##############
    #################################################
    my @file_list;
    find ( sub {
            return unless -f;       #Must be a file
            push @file_list, $File::Find::name;
            }, $this->{'uploaded_temp_folder'} );


    ################################################################
    ############### Check to see if the uploadID exists ############
    ################################################################
    ################################################################
    $query = "SELECT PatientName,TarchiveID,number_of_mincCreated,".
             "number_of_mincInserted FROM mri_upload ".
            " WHERE UploadID =?";

    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($this->{'upload_id'});
    if ($sth->rows> 0) {
        @row  = $sth->fetchrow_array();
    }
    else {
        $message = "\n The uploadID " . $this->{'upload_id'} . "Does Not Exist " .
            "Are not DiCOM";
         ###NOTE: No exit code but the Fail-status is 1  
        $this->{Log}->writeLog($message,1);
        return 0; 
    }


    ################################################################
    ############### Check to see if the scan has been ran ##########
    ###############if the tarchiveid or the number_of_mincCreated ##
    ############## It means that has already been ran###############
    ################################################################
    if (($row[1]) ||  ($row[2])) {
        $message = "\n The Scan for the uploadID " . $this->{'upload_id'} .
            " has already been ran with tarchiveID: " . $row[1];
        ###NOTE: No exit code but the Fail-status is 1  
        $this->{Log}->writeLog($message,2);
        return 0;  
    }

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

    if ($files_not_dicom > 0) {
        $message = "\n ERROR: there are $files_not_dicom files which are " .
            "Are not DiCOM";
        ###NOTE: No exit code but the Fail-status is 1  
        $this->{Log}->writeLog($message,3);
        print ($message);
        return 0;
    }
    if ($files_with_unmatched_patient_name>0) {
        $message = "\n ERROR: there are $files_with_unmatched_patient_name files".
            " where the patient-name doesn't match ";
        $this->{Log}->writeLog($message,4);
        print ($message);
        ###NOTE: No exit code but the Fail-status is 2
        return 0;
    }

    
    #############################################################
    ###############Update the MRI_upload table And###############
    ################Set the isValidated to true##################
    ########################################################
    $where = " WHERE UploadID=?";
    $query = "UPDATE mri_upload SET IsValidated=1";
    $query = $query . $where;
    my $mri_upload_update = ${$this->{'dbhr'}}->prepare($query);
    $mri_upload_update->execute($this->{'upload_id'});
    
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
        $where = "WHERE UploadID=?";
        $query = "UPDATE mri_upload SET TarchiveID='$tarchive_id'";
        $query = $query . $where;
        my $mri_upload_update = ${$this->{'dbhr'}}->prepare($query);
        $mri_upload_update->execute($this->{'upload_id'});
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

    if ($output==0) {
        return 1;
    }
    return 0;
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
    my $file_type = $this->runCommand("file $dicom_file") ;
    if (!($file_type =~/DICOM/)) {
        print "not of type DICOM";
        return 0;
    }
    return 1;
}

################################################################
###############################moveUploadedFile#################
################################################################
sub moveUploadedFile {
    my $this = shift;
    my $incoming_folder = $Settings::IncomingDir;
    my $cmd = "cp -R " . $this->{'uploaded_temp_folder'} .
        " " . $incoming_folder ;
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

################################################################
#############################removeTMPDir#######################
################################################################
sub CleanUpTMPDir {
    my $this = shift;
    ############################################################
    ####if the uploaded directory in /tmp exists################
    #############REmove it #####################################
    ############################################################
    if (-d $this->{'uploaded_temp_folder'}) {
        rmdir($this->{'uploaded_temp_folder'});
    }
}
1; 

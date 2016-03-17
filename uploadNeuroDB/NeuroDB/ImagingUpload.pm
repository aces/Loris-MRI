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
use NeuroDB::Notify;
use File::Temp qw/ tempdir /;

################################################################
#####################Constructor ###############################
################################################################
=pod
Description:
    -The constructor needs the location of the uploaded file
     Which will be in a uploaded_temp_folder and 
     once the validation passes, the File will be moved to a
     final destination directory
Arguments:
  $dbhr :
  $uploaded_temp_folder:
  $upload_id:
  $pname: 
  $profile:
=cut
sub new {
    my $params = shift;
    my ( $dbhr, $uploaded_temp_folder, $upload_id, $pname, $profile, $verbose ) = @_;
    unless ( defined $dbhr ) {
        croak( "Usage: " . $params . "->new(\$databaseHandleReference)" );
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
    ############### Create a Notify Object #####################
    ############################################################

    my $Notify = NeuroDB::Notify->new( $dbhr );
    $self->{'Notify'} = $Notify;
    $self->{'uploaded_temp_folder'} = $uploaded_temp_folder;
    $self->{'dbhr'}                 = $dbhr;
    $self->{'pname'}                = $pname;
    $self->{'upload_id'}            = $upload_id;
    $self->{'verbose'}              = $verbose;
    return bless $self, $params;
}

################################################################
#####################IsValid####################################
################################################################
=pod
IsValid()
Description:
 Validates the File to be upload:
 If the validation passes the following will happen:
  1) Copy the file from tmp folder to the /data/incoming
  2) Set the IsCandidateInfoValidated to true in the 
     mri_upload table

Arguments:
 $this: reference to the class

 Returns: 0 if the validation fails and 1 if passes
=cut
sub IsValid {
    my $this = shift;
    my ($message,$query,$where) = '';
    ############################################################
    ####Set the Inserting flag to true##########################
    #Which means that the scan is going through the pipeline####
    ############################################################
    ############################################################
    ###########Update MRI_upload Table accordingly##############
    ############################################################
    $where = " WHERE UploadID=?";
    $query = " UPDATE mri_upload SET Inserting=1";
    $query = $query . $where;
    my $mri_upload_update = ${$this->{'dbhr'}}->prepare($query);
    $mri_upload_update->execute($this->{'upload_id'});


    ############################################################
    #########################Initialization#####################
    ############################################################
    my $files_not_dicom                   = 0;
    my $files_with_unmatched_patient_name = 0;
    my $is_valid                          = 0;
    my @row                               = ();

    ############################################################
    ####Get a list of files from the folder#####################
    ############################################################
    ############################################################
    #############Loop through the files#########################
    ############################################################
    my @file_list;
    find(
        sub {
            return unless -f;    #Must be a file
            push @file_list, $File::Find::name;
        },
        $this->{'uploaded_temp_folder'}
    );
    ############################################################
    ############### Check to see if the uploadID exists ########
    ############################################################
    ############################################################
    $query =
        "SELECT PatientName,TarchiveID,number_of_mincCreated,"
      . "number_of_mincInserted,IsPhantom FROM mri_upload "
      . " WHERE UploadID =?";
    my $sth = ${ $this->{'dbhr'} }->prepare($query);
    $sth->execute( $this->{'upload_id'} );
    if ( $sth->rows > 0 ) {
        @row = $sth->fetchrow_array();
    }
    else {
        $message =
            "\n The uploadID "
          . $this->{'upload_id'}
          . "Does Not Exist ";
        $this->spool($message, 'Y');
        return 0;
    }

    ############################################################
    ####Check to see if the scan has been ran ##################
    ####if the tarchiveid or the number_of_mincCreated is set ##
    ####itt means that has already been ran#####################
    ############################################################
    if ( ( $row[1] ) || ( $row[2] ) ) {

        $message =
            "\n The Scan for the uploadID "
          . $this->{'upload_id'}
          . " has already been ran with tarchiveID: "
          . $row[1];
        $this->spool($message, 'Y');
        return 0;
    }


    foreach (@file_list) {
        ########################################################
        #1) Check to see if the file is of type DICOM###########
        #2) Check to see if the header matches the patient-name#
        ########################################################
        if ( ( $_ ne '.' ) && ( $_ ne '..' ) ) {
            if ( !$this->isDicom($_) ) {
                $files_not_dicom++;
            }
         #######################################################
         #Validate the Patient-Name, only if it's not a phantom#
         #######################################################
	    if ($row[4] eq 'N') {
            	if ( !$this->PatientNameMatch($_) ) {
	        	$files_with_unmatched_patient_name++;
	        }

	    }
        }
    }

    if ( $files_not_dicom > 0 ) {
        $message = "\n ERROR: there are $files_not_dicom files which are "
          . "Are not of type DICOM";
        $this->spool($message, 'Y');
        return 0;
    }

    if ( $files_with_unmatched_patient_name > 0 ) {
        $message =
            "\n ERROR: there are $files_with_unmatched_patient_name files"
          . " where the patient-name doesn't match ";
        $this->spool($message, 'Y');
        return 0;
    }

    ############################################################
    ###############Update the MRI_upload table and##############
    #########set the IsCandidatInfoValidated to true############
    ############################################################
    $where = " WHERE UploadID=?";
    $query = "UPDATE mri_upload SET IsCandidateInfoValidated=1";
    $query = $query . $where;
    $mri_upload_update = ${ $this->{'dbhr'} }->prepare($query);
    $mri_upload_update->execute( $this->{'upload_id'} );
    return 1;    ##return true
}


################################################################
############################runDicomTar#########################
################################################################
=pod
runDicomTar()
Description:
 -Extracts tarchiveID using pname
 -Runs dicomTar.pl with -clobber -database -profile prod options
 -If successfull it updates MRI_upload table accordingly

Arguments:
 $this: reference to the class

 Returns: 0 if the validation fails and 1 if it passes
=cut
sub runDicomTar {
    my $this              = shift;
    my $tarchive_id       = '';
    my $query             = '';
    my $where             = '';
    my $tarchive_location = $Settings::tarchiveLibraryDir;
    my $dicomtar = 
      $Settings::bin_dir . "/" . "dicom-archive" . "/" . "dicomTar.pl";
    my $command =
        $dicomtar . " " . $this->{'uploaded_temp_folder'} 
      . " $tarchive_location -clobber -database -profile prod";
    my $output = $this->runCommandWithExitCode($command);

    if ( $output == 0 ) {

        ########################################################
        ##########Extract tarchiveID using pname################
        ########################################################

        $query = "SELECT TarchiveID FROM tarchive WHERE SourceLocation =?";
        my $sth = ${ $this->{'dbhr'} }->prepare($query);
        $sth->execute( $this->{'uploaded_temp_folder'} );
        if ( $sth->rows > 0 ) {
            $tarchive_id = $sth->fetchrow_array();
        }

        ########################################################
        #################Update MRI_upload table accordingly####
        ########################################################
        $where = "WHERE UploadID=?";
        $query = "UPDATE mri_upload SET TarchiveID='$tarchive_id'";
        $query = $query . $where;
        my $mri_upload_update = ${ $this->{'dbhr'} }->prepare($query);
        $mri_upload_update->execute( $this->{'upload_id'} );
        return 1;
    }
    return 0;
}

################################################################
###################getTarchiveFileLocation######################
################################################################
=pod
getTarchiveFileLocation()
Description:
 -Extracts tarchiveID using pname
 -Runs dicomTar.pl with clobber -database -profile prod options
 -If successfull it updates MRI_upload Table accordingly

Arguments:
 $this: reference to the class

 Returns: 0 if the validation fails and 1 if passes
=cut
sub getTarchiveFileLocation {
    my $this             = shift;
    my $archive_location = '';
    my $query            = "SELECT t.ArchiveLocation FROM tarchive t "
                           . " WHERE t.SourceLocation =?";
    my $sth              = ${ $this->{'dbhr'} }->prepare($query);
    $sth->execute( $this->{'uploaded_temp_folder'} );
    if ( $sth->rows > 0 ) {
        $archive_location = $sth->fetchrow_array();
    }

    unless ($archive_location =~ m/$Settings::tarchiveLibraryDir/i) {
        $archive_location = ($Settings::tarchiveLibraryDir . "/" . $archive_location);
    }

    return $archive_location;
}

################################################################
######################runTarchiveLoader#########################
################################################################
=pod
 runTarchiveLoader()
Description:
 -Runs tarchiveLoader with clobber -profile prod option
 -If successfull it updates MRI_upload Table accordingly

Arguments:
 $this: reference to the class

 Returns: 0 if the validation fails and 1 if passes
=cut

sub runTarchiveLoader {
    my $this               = shift;
    my $archived_file_path = $this->getTarchiveFileLocation();
    my $command =
        $Settings::bin_dir
      . "/uploadNeuroDB/tarchiveLoader"
      . " -globLocation -profile prod $archived_file_path";
    my $output = $this->runCommandWithExitCode($command);
    if ( $output == 0 ) {
        return 1;
    }
    return 0;
}

################################################################
#########################PatientNameMatch#######################
################################################################
=pod
PatientNameMatch()
Description:
 - Extracts the patientname string from the dicom file header
   using dcmdump
 - Uses regex to parse the string in order to the get the appropriate 
   patientname from the obtained string
 - returns the 1 if the extracted patient-name matches
   $this->{'pname'} object, 0 otherwise

Arguments:
 $this: reference to the class
 $dicom_file: The full path to the dicom-file

 Returns: 0 if the validation fails and 1 if passes
=cut

sub PatientNameMatch {
    my $this         = shift;
    my ($dicom_file) = @_;
    my $cmd          = "dcmdump $dicom_file | grep PatientName";

    my $patient_name_string = $this->runCommand($cmd);
    if (!($patient_name_string)) {
	    my $message = "the patientname cannot be extracted";
        $this->spool($message, 'Y');
        exit 1;
    }
    my ($l,$pname,$t) = split /\[(.*?)\]/, $patient_name_string;
    if ($pname ne  $this->{'pname'}) {
        my $message = "The patient-name $pname does not Match " .
            $this->{'pname'};
    $this->spool($message, 'Y');
        return 0; ##return false
    }
    return 1;     ##return true

}

################################################################
########################isDicom#################################
################################################################
=pod
isDicom()
Description:
 - checks to see if the file is of type DICOM 

Arguments:
 $this: reference to the class
 $dicom_file: The path to the dicom-file

 Returns: 0 if the file is not of type DICOM and 1 otherwise
=cut

sub isDicom {
    my $this         = shift;
    my ($dicom_file) = @_;
    my $file_type    = $this->runCommand("file $dicom_file");
    if ( !( $file_type =~ /DICOM/ ) ) {
        print "not of type DICOM" if $this->{'verbose'};
        return 0;
    }
    return 1;
}

################################################################
####################sourceEnvironment###########################
################################################################
=pod
sourceEnvironment()
Description:
   - sources the environment file 

Arguments:
 $this      : Reference to the class

 Returns    : NULL
=cut

sub sourceEnvironment {
    my $this            = shift;
    my $cmd =   "source  " . $Settings::bin_dir."/". "environment";
    $this->runCommand($cmd);
}


################################################################
#######################runCommandWithExitCode###################
################################################################
=pod
runCommandWithExitCode()
Description:
   - Runs the linux command using system and 
     returns the proper exit code 

Arguments:
 $this      : Reference to the class
 $command   : The linux command to be executed

 Returns    : NULL

=cut

sub runCommandWithExitCode {
    my $this = shift;
    my ($command) = @_;
    print "\n\n $command \n\n " if $this->{'verbose'};
    my $output = system($command);
    return $output >> 8;    ##returns the exit code
}

################################################################
######################runCommand################################
################################################################
=pod
runCommand()
Description:
   - Runs the linux command using back-tilt
   - Note: Backtilt return value is STDOUT 

Arguments:
 $this      : Reference to the class
 $command   : The linux command to be executed

 Returns    : NULL
=cut

sub runCommand {
    my $this = shift;
    my ($command) = @_;
    print "\n\n $command \n\n " if $this->{'verbose'};
    return `$command`;
}

################################################################
####################CleanUpDataIncomingDir######################
################################################################
=pod
CleanUpDataIncomingDir()
Description:
   - Cleans Up and removes the uploaded file from the data  
     directory once it is inserted into the database

Arguments:
 $this      : Reference to the class

Returns: 1 if the uploaded file removal was successful and 0 otherwise

=cut

sub CleanUpDataIncomingDir {
    my $this = shift;
    my ($uploaded_file) = @_;
    my $output = undef;
    my $message = '';
    my $tarchive_location = $Settings::tarchiveLibraryDir;
    ############################################################
    ################ Removes the uploaded file ################# 
    ##### Check first that the file is in the tarchive dir ##### 
    ############################################################

    my $base_decompressed_loc = basename($this->{'uploaded_temp_folder'}); 
    my $command = "find " . $tarchive_location . "/ " . "-name *" . 
		   $base_decompressed_loc . "*";
    my $tarchive_file = $this->runCommand($command);
    if ($tarchive_file) {
        $command = "rm " . $uploaded_file;
        my $output = $this->runCommandWithExitCode($command);
        if (!$output) {
            $message =
                "The following file " . $tarchive_file . " was found\n";
            $this->spool($message, 'N');
            return 1;
        }
        $message =
            "Unable to remove the file:" . $uploaded_file . "\n";
        $this->spool($message, 'Y');
        return 0;
        }
    else {
        $message =
            "The file " . $tarchive_file . " can not be found\n";
        $this->spool($message, 'Y');
        return 0; # if the file was not found in tarchive, do not delete the original
    }

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
 Returns    : NULL
=cut

sub spool  {
    my $this = shift;
    my ( $message, $error ) = @_;
    print "message is $message \n";
    $this->{'Notify'}->spool('mri upload processing class', $message, 0,
           'Imaging_Upload.pm', $this->{'upload_id'},$error);
}


################################################################
#################updateMRIUploadTable###########################
################################################################
=pod
updateMRIUploadTable()
Description:
   - Update the mri_upload table 

Arguments:
 $this      : Reference to the class
 $field     : Name of the column in the table 
 $value     : Value of the column to be set
 Returns    : NULL
=cut

sub updateMRIUploadTable  {
    my $this = shift;

    my ( $field, $value ) = @_;
        ########################################################
        #################Update MRI_upload table accordingly####
        ########################################################
        my $where = "WHERE UploadID=?";
        my $query = "UPDATE mri_upload SET $field=?";
        $query = $query . $where;
        my $mri_upload_update = ${ $this->{'dbhr'} }->prepare($query);
        $mri_upload_update->execute( $value,$this->{'upload_id'} );
}

1;

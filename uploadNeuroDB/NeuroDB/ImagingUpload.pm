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

## Define Constants ##
my $notify_detailed   = 'Y'; # notification_spool message flag for messages to be displayed 
                             # with DETAILED OPTION in the front-end/imaging_uploader 
my $notify_notsummary = 'N'; # notification_spool message flag for messages to be displayed 
                             # with SUMMARY Option in the front-end/imaging_uploader 

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

    my $Notify 			    = NeuroDB::Notify->new( $dbhr );
    $self->{'Notify'} 		    = $Notify;
    $self->{'uploaded_temp_folder'} = $uploaded_temp_folder;
    $self->{'dbhr'}                 = $dbhr;
    $self->{'pname'}                = $pname;
    $self->{'upload_id'}            = $upload_id;
    $self->{'verbose'}              = $verbose;
    return bless $self, $params;
}

################################################################
#####################IsCandidateInfoValid#######################
################################################################
=pod
IsCandidateInfoValid()
Description:
 Validates the File to be uploaded:
 If the validation passes the following will happen:
  1) Copy the file from tmp folder to the /data/incoming
  2) Set the IsCandidateInfoValidated to true in the 
     mri_upload table

Arguments:
 $this: reference to the class

 Returns: 0 if the validation fails and 1 if passes
=cut
sub IsCandidateInfoValid {
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
    my $is_candinfovalid                  = 0;
    my @row                               = ();
    ############################################################
    ####Get a list of files from the folder#####################
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
            "\nThe uploadID "
          . $this->{'upload_id'}
          . " Does Not Exist \n";
        $this->spool($message, 'Y', $notify_notsummary);
        return 0;
    }

    ############################################################
    ####Check to see if the scan has been run ##################
    ####if the tarchiveid or the number_of_mincCreated is set ##
    ####it means that has already been run. ####################
    ####So the user can continue the insertion by running ######
    ####tarchiveLoader exactly as the error message indicates ##
    ############################################################
    if ( ( $row[1] ) || ( $row[2] ) ) {

        my $archived_file_path = '';
        my $query             = "SELECT t.ArchiveLocation FROM tarchive t "
                              . " WHERE t.TarchiveID =?";
        my $sth               = ${ $this->{'dbhr'} }->prepare($query);
        $sth->execute( $row[1] );   
        if ( $sth->rows > 0 ) {
            $archived_file_path = $sth->fetchrow_array();
        }
        my $tarchivePath = NeuroDB::DBI::getConfigSetting(
                            $this->{dbhr},'tarchiveLibraryDir'
                            );
        my $bin_dirPath = NeuroDB::DBI::getConfigSetting(
                            $this->{dbhr},'MRICodePath'
                            );
        unless ($archived_file_path =~ m/$tarchivePath/i) {
            $archived_file_path = ($tarchivePath . "/" . $archived_file_path);
        }

        my $command =
            $bin_dirPath
            . "/uploadNeuroDB/tarchiveLoader"
            . " -globLocation -profile prod $archived_file_path";

        if ($this->{verbose}){
            $command .= " -verbose";
        }

        $message =
            "\nThe Scan for the uploadID "
            . $this->{'upload_id'}
            . " has already been run with tarchiveID: "
            . $row[1]
            . ". \nTo continue with the rest of the insertion pipeline, "
            . "please run tarchiveLoader from a terminal as follows: "
            . $command 
            . "\n";
        $this->spool($message, 'Y', $notify_notsummary);
        return 0;
    }


    ############################################################
    ####Remove __MACOSX directory from the upload ##############
    ############################################################
    my $cmd = "cd " . $this->{'uploaded_temp_folder'} . "; find -name '__MACOSX' | xargs rm -rf";
    system($cmd);

    foreach (@file_list) {
        ########################################################
        #1) Exlcude files starting with . (and ._ as a result)##
        #including the .DS_Store file###########################
        #2) Check to see if the file is of type DICOM###########
        #3) Check to see if the header matches the patient-name#
        ########################################################
        if ( (basename($_) =~ /^\./)) {
            $cmd = "rm " . ($_);
            print ($cmd);
            system($cmd);
        }
        else {
            if ( ( $_ ne '.' ) && ( $_ ne '..' )) {
                if ( !$this->isDicom($_) ) {
                    $files_not_dicom++;
                }
    	        else {
            #######################################################
            #Validate the Patient-Name, only if it's not a phantom#
            ############## and the file is of type DICOM###########
            #######################################################
                    if ($row[4] eq 'N') {
                        if ( !$this->PatientNameMatch($_) ) {
                                $files_with_unmatched_patient_name++;
                        }
                    }
                }
            }
        }
    }

    if ( $files_not_dicom > 0 ) {
        $message = "\nERROR: There are $files_not_dicom file(s) which"
          . " are not of type DICOM \n";
        $this->spool($message, 'Y', $notify_notsummary);
        return 0;
    }

    if ( $files_with_unmatched_patient_name > 0 ) {
        $message =
            "\nERROR: There are $files_with_unmatched_patient_name file(s)"
          . " where the patient-name doesn't match \n";
        $this->spool($message, 'Y', $notify_notsummary);
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
    my $tarchive_id       = undef;
    my $query             = '';
    my $where             = '';
    my $tarchive_location = NeuroDB::DBI::getConfigSetting(
                            $this->{dbhr},'tarchiveLibraryDir'
                            );
    my $bin_dirPath = NeuroDB::DBI::getConfigSetting(
                        $this->{dbhr},'MRICodePath'
                        );
    my $dicomtar = 
      $bin_dirPath . "/" . "dicom-archive" . "/" . "dicomTar.pl";
    my $command =
        $dicomtar . " " . $this->{'uploaded_temp_folder'} 
      . " $tarchive_location -clobber -database -profile prod";
    if ($this->{verbose}) {
        $command .= " -verbose";
    }
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

    my $tarchive_location = NeuroDB::DBI::getConfigSetting(
                            $this->{dbhr},'tarchiveLibraryDir'
                            );
    unless ($archive_location =~ m/$tarchive_location/i) {
        $archive_location = ($tarchive_location . "/" . $archive_location);
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
    my $bin_dirPath = NeuroDB::DBI::getConfigSetting(
                        $this->{dbhr},'MRICodePath'
                        );
    my $command =
        $bin_dirPath
      . "/uploadNeuroDB/tarchiveLoader.pl"
      . " -globLocation -profile prod $archived_file_path";

    if ($this->{verbose}){
        $command .= " -verbose";
    }
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
    my $patient_name_string =  `$cmd`;
    if (!($patient_name_string)) {
	my $message = "\nThe patient name cannot be extracted \n";
        $this->spool($message, 'Y', $notify_notsummary);
        exit 1;
    }
    my ($l,$pname,$t) = split /\[(.*?)\]/, $patient_name_string;
    if ($pname !~ /^$this->{'pname'}/) {
        my $message = "\nThe patient-name read ".
                      "from the DICOM header does not start with " .
        	      $this->{'pname'} . 
                      " from the mri_upload table\n";
    	$this->spool($message, 'Y', $notify_notsummary);
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
    my $cmd    = "file $dicom_file";
    my $file_type    = `$cmd`;
    if ( !( $file_type =~ /DICOM medical imaging data$/ ) ) {
        print "\n $dicom_file is not of type DICOM \n";
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
    my $bin_dirPath = NeuroDB::DBI::getConfigSetting(
                        $this->{dbhr},'MRICodePath'
                        );
    my $cmd =   "source  " . $bin_dirPath."/". "environment";
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
    print "\n$command \n " if $this->{'verbose'};
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
    print "\n$command \n " if $this->{verbose};
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
    my $tarchive_location = NeuroDB::DBI::getConfigSetting(
                                $this->{dbhr},'tarchiveLibraryDir'
                            );
    ############################################################
    ################ Removes the uploaded file ################# 
    ##### Check first that the file is in the tarchive dir ##### 
    ############################################################

    my $base_decompressed_loc = basename($this->{'uploaded_temp_folder'}); 
    my $command = "find " . $tarchive_location . "/ " . "-name *" . 
		   $base_decompressed_loc . "*";
    my $tarchive_file = $this->runCommand($command);
    if ($tarchive_file) {
        $message =
            "\nThe following file " . $tarchive_file . " was found\n";
        $this->spool($message, 'N', $notify_detailed);
        $command = "rm " . $uploaded_file;
        my $output = $this->runCommandWithExitCode($command);
        if (!$output) {
            return 1;
        }
        $message =
            "\nUnable to remove the file:" . $uploaded_file . "\n";
        $this->spool($message, 'Y', $notify_notsummary);
        return 0;
    }
    else {
        $message =
            "\nThe file " . $tarchive_file . " can not be found\n";
        $this->spool($message, 'Y', $notify_notsummary);
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
 $verb      : 'N' for few main messages, 'Y' for more messages (developers)
 Returns    : NULL
=cut

sub spool  {
    my $this = shift;
    my ( $message, $error, $verb ) = @_;

    if ($error eq 'Y'){
        print "Spool message is: $message \n";
    }
    $this->{'Notify'}->spool('mri upload processing class', $message, 0,
           'ImagingUpload.pm', $this->{'upload_id'},$error,$verb);
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

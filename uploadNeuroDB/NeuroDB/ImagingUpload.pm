package NeuroDB::ImagingUpload;


=pod

=head1 NAME

NeuroDB::ImagingUpload -- Provides an interface to the uploaded imaging file

=head1 SYNOPSIS

  use NeuroDB::ImagingUpload;

  my $imaging_upload = &NeuroDB::ImagingUpload->new(
                         \$dbh,
                         $TmpDir_decompressed_folder,
                         $upload_id,
                         $patient_name,
                         $profile,
                         $verbose
                       );

  my $is_candinfovalid = $imaging_upload->IsCandidateInfoValid();

  my $output = $imaging_upload->runDicomTar();
  $imaging_upload->updateMRIUploadTable('Inserting', 0) if ( !$output );


  my $output = $imaging_upload->runTarchiveLoader();
  $imaging_upload->updateMRIUploadTable('Inserting', 0) if ( !$output);

  my $isCleaned = $imaging_upload->CleanUpDataIncomingDir($uploaded_file);


=head1 DESCRIPTION

This library regroups utilities for manipulation of the uploaded imaging file
and updates of the C<mri_upload> table according to the upload status.

=head2 Methods

=cut

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
use NeuroDB::ExitCodes;
use NeuroDB::DBI;
use NeuroDB::MRI;
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

=head3 new($dbhr, $uploaded_temp_folder, $upload_id, ...) >> (constructor)

Creates a new instance of this class. This constructor needs the location of
the uploaded file. Once the uploaded file has been validated, it will be
moved to a final destination directory.

INPUTS:
  - $dbhr                : database handler
  - $uploaded_temp_folder: temporary directory of the upload
  - $upload_id           : C<uploadID> from the C<mri_upload> table
  - $pname               : patient name
  - $profile             : name of the configuration file in
                            C</data/$PROJECT/data> (typically C<prod>)

RETURNS: new instance of this class

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


=pod

=head3 IsCandidateInfoValid()

Validates the File to be uploaded. If the validation passes, the following
actions will happen:
  1) Copy the file from C<tmp> folder to C</data/incoming>
  2) Set C<IsCandidateInfoValidated> to TRUE in the C<mri_upload> table

RETURNS: 1 on success, 0 on failure

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
    my $files_with_unmatched_patient_name = 0;
    my @row                               = ();

    ############################################################
    ####Remove __MACOSX directory from the upload if found######
    ####Get a list of files from the folder#####################
    #############Loop through the files#########################
    ############################################################
    my $cmd = "find -path " . quotemeta($this->{'uploaded_temp_folder'}) . " -name '__MACOSX' -delete ";
    print "\n $cmd \n";
    system($cmd);

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

        my $command = sprintf(
            "%s/uploadNeuroDB/tarchiveLoader -globLocation -profile %s %s -uploadID %s",
            quotemeta($bin_dirPath),
            'prod',
            quotemeta($archived_file_path),
            quotemeta($this->{upload_id})
        );
        $command .= " -verbose" if $this->{verbose};

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

    my $isImage_hash    = NeuroDB::MRI::isDicomImage(@file_list);
    my @image_files     = grep { $$isImage_hash{$_} == 1 } keys %$isImage_hash;
    my @non_image_files = grep { $$isImage_hash{$_} == 0 } keys %$isImage_hash;
    
    # Issue warnings for files that are not DICOM images
    foreach my $f (@non_image_files) {
        $message = "\nWARNING: file '$f' is not a DICOM image: ignored.\n";
        $this->spool($message, 'N', $notify_notsummary);
	}
	
	# Issue a warning for the total number of files that are not
	# DICOM images
    my $files_not_dicom = scalar @non_image_files;
    if ($files_not_dicom > 0 ) {
        $message = "\nWARNING: There are $files_not_dicom file(s) which"
                   . " are not DICOM images: these will be ignored.\n";
        $this->spool($message, 'N', $notify_notsummary);
    }

    # check that the patient name was set properly in the DICOM files
    my $lego_phantom_regex = NeuroDB::DBI::getConfigSetting(
        $this->{dbhr}, 'LegoPhantomRegex'
    );
    my $living_phantom_regex = NeuroDB::DBI::getConfigSetting(
        $this->{dbhr}, 'LivingPhantomRegex'
    );
    my $phantom_regex = "($lego_phantom_regex)|($living_phantom_regex)";
    my $patient_name  = $this->{'pname'};
    foreach my $file (@image_files) {
        if ($row[4] eq 'N' && !$this->PatientNameMatch($file, "^$patient_name")) {
            $files_with_unmatched_patient_name++;
        } elsif ($row[4] eq 'Y' && !$this->PatientNameMatch($file, $phantom_regex)) {
            $files_with_unmatched_patient_name++;
        }
    }

    # return 0 if found at least one DICOM file without the proper patient name
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



=pod

=head3 runDicomTar()

This method executes the following actions:
 - Runs C<dicomTar.pl> with C<-database -profile prod> options
 - Extracts the C<TarchiveID> of the DICOM archive created by C<dicomTar.pl>
 - Updates the C<mri_upload> table if C<dicomTar.pl> ran successfully

RETURNS: 1 on success, 0 on failure

=cut

sub runDicomTar {
    my $this              = shift;
    my $tarchive_id       = undef;
    my $query             = '';
    my $where             = '';
    my $tarchive_location = NeuroDB::DBI::getConfigSetting(
                            $this->{dbhr},'tarchiveLibraryDir'
                            );
    my $command = sprintf(
        "dicomTar.pl %s %s -database -profile %s",
        quotemeta($this->{'uploaded_temp_folder'}),
        quotemeta($tarchive_location),
        'prod'
    );
    $command .= " -verbose" if $this->{verbose};
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


=pod

=head3 getTarchiveFileLocation()

This method fetches the location of the archive from the C<tarchive> table of
the database.

RETURNS: the archive location

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


=pod

=head3 runTarchiveLoader()

This methods will call C<tarchiveLoader> with the C<-clobber -profile prod>
options and update the C<mri_upload> table accordingly if C<tarchiveLoader> ran
successfully.

RETURNS: 1 on success, 0 on failure

=cut

sub runTarchiveLoader {
    my $this = shift;
    my $archived_file_path = $this->getTarchiveFileLocation();
    my $bin_dirPath = NeuroDB::DBI::getConfigSetting(
                        $this->{dbhr},'MRICodePath'
                        );
    my $command = sprintf(
        "%s/uploadNeuroDB/tarchiveLoader -globLocation -profile %s %s -uploadID %s",
        quotemeta($bin_dirPath),
        'prod',
        quotemeta($archived_file_path),
        quotemeta($this->{upload_id})
    );
    $command .= " -verbose" if $this->{verbose};
    my $output = $this->runCommandWithExitCode($command);
    if ( $output == 0 ) {
        return 1;
    }
    return 0;
}


=pod

=head3 PatientNameMatch($dicom_file, $expected_pname_regex)

This method extracts the patient name field from the DICOM file header using
C<dcmdump> and compares it with the patient name information stored in the
C<mri_upload> table.

INPUTS:
  - $dicom_file          : full path to the DICOM file
  - $expected_pname_regex: expected patient name regex to find in the DICOM file

RETURNS: 1 on success, 0 on failure

=cut

sub PatientNameMatch {
    my $this         = shift;
    my ($dicom_file, $expected_pname_regex) = @_;

    my $lookupCenterNameUsing = NeuroDB::DBI::getConfigSetting(
        $this->{'dbhr'},'lookupCenterNameUsing'
    );

    unless ( $lookupCenterNameUsing ) {
        my $message = "\nConfig Setting 'lookupCenterNameUsing' is not set in "
                      . "the Config module under the Imaging Pipeline section.";
        $this->spool($message, 'Y', $notify_notsummary);
        exit $NeuroDB::ExitCodes::MISSING_CONFIG_SETTING;
    }

    unless ($lookupCenterNameUsing =~ /^(PatientName|PatientID)$/i) {
        my $message = "\nConfig setting 'lookupCenterNameUsing' is set to "
                      . "$lookupCenterNameUsing but should be set to "
                      . "either PatientID or PatientName";
        $this->spool($message, 'Y', $notify_notsummary);
        exit $NeuroDB::ExitCodes::BAD_CONFIG_SETTING;
    }

    my $cmd = sprintf("dcmdump +P %s -q %s",
        quotemeta($lookupCenterNameUsing), quotemeta($dicom_file)
    );
    my $patient_name_string =  `$cmd`;
    if (!($patient_name_string)) {
	    my $message = "\nThe '$lookupCenterNameUsing' DICOM field cannot be "
	                  . "extracted from the DICOM file $dicom_file\n";
        $this->spool($message, 'Y', $notify_notsummary);
        exit $NeuroDB::ExitCodes::DICOM_PNAME_EXTRACTION_FAILURE;
    }
    my ($l,$dicom_pname,$t) = split /\[(.*?)\]/, $patient_name_string;
    if ($dicom_pname !~ /$expected_pname_regex/) {
        my $message = "\nThe $lookupCenterNameUsing read "
                      . "from the DICOM header does not start with "
                      . $expected_pname_regex
                      . " from the mri_upload table\n";
    	$this->spool($message, 'Y', $notify_notsummary);
        return 0; ##return false
    }
    return 1;     ##return true

}

=pod

=head3 runCommandWithExitCode($command)

This method will run any linux command given as an argument using the
C<system()> method and will return the proper exit code.

INPUT: the linux command to be executed

RETURNS: the exit code of the command

=cut

sub runCommandWithExitCode {
    my $this = shift;
    my ($command) = @_;
    print "\n$command \n " if $this->{'verbose'};
    my $output = system($command);
    return $output >> 8;    ##returns the exit code
}


=pod

=head3 runCommand($command)

This method will run any linux command given as an argument using back-tilt
and will return the back-tilt return value (which is C<STDOUT>).

INPUT: the linux command to be executed

RETURNS: back-tilt return value (C<STDOUT>)

=cut

sub runCommand {
    my $this = shift;
    my ($command) = @_;
    print "\n$command \n " if $this->{verbose};
    return `$command`;
}


=pod

=head3 CleanUpDataIncomingDir($uploaded_file)

This method cleans up and removes the uploaded file from the data directory
once the uploaded file has been inserted into the database and saved in the
C<tarchive> folder.

RETURNS: 1 on success, 0 on failure

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


=pod

=head3 spool($message, $error, $verb)

This method calls the C<< Notify->spool >> function to log all messages
returned by the insertion scripts.

INPUTS:
 - $message: message to be logged in the database
 - $error  : 'Y' for an error log ,
             'N' otherwise
 - $verb   : 'N' for few main messages,
             'Y' for more messages (for developers)

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


=pod

=head3 updateMRIUploadTable($field, $value)

This method updates the C<mri_upload> table with C<$value> for the field
C<$field>.

INPUTS:
 - $field: name of the column in the table to be updated
 - $value: value of the column to be set

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


=pod

=head1 COPYRIGHT AND LICENSE

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut

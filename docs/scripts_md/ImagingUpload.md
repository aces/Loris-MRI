# NAME

NeuroDB::ImagingUpload -- Provides an interface to the uploaded imaging file

# SYNOPSIS

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

# DESCRIPTION

This library regroups utilities for manipulation of the uploaded imaging file
and updates of the `mri_upload` table according to the upload status.

## Methods

### new($dbhr, $uploaded\_temp\_folder, $upload\_id, ...) >> (constructor)

Creates a new instance of this class. This constructor needs the location of
the uploaded file. Once the uploaded file has been validated, it will be
moved to a final destination directory.

INPUTS:
  - $dbhr                : database handler
  - $uploaded\_temp\_folder: temporary directory of the upload
  - $upload\_id           : `uploadID` from the `mri_upload` table
  - $pname               : patient name
  - $profile             : name of the configuration file in
                            `/data/$PROJECT/data` (typically `prod`)

RETURNS: new instance of this class

### IsCandidateInfoValid()

Validates the File to be uploaded. If the validation passes, the following
actions will happen:
  1) Copy the file from `tmp` folder to `/data/incoming`
  2) Set `IsCandidateInfoValidated` to TRUE in the `mri_upload` table

RETURNS: 1 on success, 0 on failure

### runDicomTar()

This method executes the following actions:
 - Runs `dicomTar.pl` with `-database -profile prod` options
 - Extracts the `TarchiveID` of the DICOM archive created by `dicomTar.pl`
 - Updates the `mri_upload` table if `dicomTar.pl` ran successfully

RETURNS: 1 on success, 0 on failure

### getTarchiveFileLocation()

This method fetches the location of the archive from the `tarchive` table of
the database.

RETURNS: the archive location

### runTarchiveLoader()

This methods will call `tarchiveLoader.pl` with the `-clobber -profile prod`
options and update the `mri_upload` table accordingly if `tarchiveLoader.pl` ran
successfully.

RETURNS: 1 on success, 0 on failure

### PatientNameMatch($dicom\_file, $expected\_pname\_regex)

This method extracts the patient name field from the DICOM file header using
`dcmdump` and compares it with the patient name information stored in the
`mri_upload` table.

INPUTS:
  - $dicom\_file          : full path to the DICOM file
  - $expected\_pname\_regex: expected patient name regex to find in the DICOM file

RETURNS: 1 on success, 0 on failure

### runCommandWithExitCode($command)

This method will run any linux command given as an argument using the
`system()` method and will return the proper exit code.

INPUT: the linux command to be executed

RETURNS: the exit code of the command

### runCommand($command)

This method will run any linux command given as an argument using back-tilt
and will return the back-tilt return value (which is `STDOUT`).

INPUT: the linux command to be executed

RETURNS: back-tilt return value (`STDOUT`)

### CleanUpDataIncomingDir($uploaded\_file)

This method cleans up and removes the uploaded file from the data directory
once the uploaded file has been inserted into the database and saved in the
`tarchive` folder.

RETURNS: 1 on success, 0 on failure

### spool($message, $error, $verb)

This method calls the `Notify->spool` function to log all messages
returned by the insertion scripts.

INPUTS:
 - $message: message to be logged in the database
 - $error  : 'Y' for an error log ,
             'N' otherwise
 - $verb   : 'N' for few main messages,
             'Y' for more messages (for developers)

### updateMRIUploadTable($field, $value)

This method updates the `mri_upload` table with `$value` for the field
`$field`.

INPUTS:
 - $field: name of the column in the table to be updated
 - $value: value of the column to be set

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

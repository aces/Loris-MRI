# NAME

imaging\_upload\_file.pl -- a single step script for the imaging pre-processing
and insertion pipeline sequence

# SYNOPSIS

perl imaging\_upload\_file.pl &lt;/path/to/UploadedFile> `[options]`

Available options are:

\-profile      : name of the config file in `../dicom-archive/.loris_mri`

\-upload\_id    : The Upload ID of the given scan uploaded

\-verbose      : if set, be verbose

# DESCRIPTION

The program does the following:

\- Gets the location of the uploaded file (.zip, .tar.gz or .tgz)

\- Unzips the uploaded file

\- Uses the `ImagingUpload` class to:
   1) Validate the uploaded file   (set the validation to true)
   2) Run `dicomTar.pl` on the file  (set the `dicomTar` to true)
   3) Run `tarchiveLoader.pl` on the file (set the minc-created to true)
   4) Remove the uploaded file once the previous steps have completed
   5) Update the `mri_upload` table

## Methods

### getPnameUsingUploadID($upload\_id)

Function that gets the patient name using the upload ID

INPUT: The upload ID

RETURNS: The patient name

### getFilePathUsingUploadID($upload\_id)

Functions that gets the file path from the \`mri\_upload\` table using the upload
ID

INPUT: The upload ID

RETURNS: The full path to the uploaded file

### getNumberOfMincFiles($upload\_id)

Function that gets the count of MINC files created and inserted using the
upload ID

INPUT: The upload ID

RETURNS:
  - $minc\_created : count of MINC files created
  - $minc\_inserted: count of MINC files inserted

### spool()

Function that calls the `Notify-`spool> function to log all messages

INPUTS:
 - $this   : Reference to the class
 - $message: Message to be logged in the database
 - $error  : If 'Y' it's an error log , 'N' otherwise
 - $verb   : 'N' for summary messages,
             'Y' for detailed messages (developers)

# TO DO

Add a check that the uploaded scan file is accessible by the front end user
(i.e. that the user-group is set properly on the upload directory). Throw an
error and log it, otherwise.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

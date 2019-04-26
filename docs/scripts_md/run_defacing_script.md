# NAME

run\_defacing.pl -- a script that creates defaced images for anatomical
acquisitions specified in the Config module of LORIS.

# SYNOPSIS

`perl tools/run_defacing_script.pl [options]`

Available options are:

`-profile`     : name of the config file in `../dicom-archive/.loris_mri`

`-tarchive_ids`: comma-separated list of MySQL `TarchiveID`s

`-verbose`     : be verbose

# DESCRIPTION

This script will create defaced images for anatomical acquisitions that are
specified in the Config module of LORIS.

# METHODS

### grep\_FileIDs\_to\_deface($session\_id\_arr, $modalities\_to\_deface\_arr)

Queries the database for the list of acquisitions' FileID to be used to run the
defacing algorithm based on the provided list of SessionID and Scan\_type to
restrict the search.

INPUTS:
  - $session\_id\_arr          : array of SessionIDs to use when grepping FileIDs
  - $modalities\_to\_deface\_arr: array of Scan\_type to use when grepping FileIDs

RETURNS: hash of matching FileIDs to be used to run the defacing algorithm
         organized in a hash as follows:

    {0123}                          # sessionID key
        {flair}                     # flair scan type key
            {$FileID} = $File_path  # key = FileID; value = MINC file path
        {t1}                        # t1 scan type key
            {$FileID} = $File_path  # key = FileID 1; value = MINC file 1 path
            {$FileID} = $File_path  # key = FileID 2; value = MINC file 2 path

### grep\_candID\_visit\_from\_SessionID($session\_id)

Greps the candidate's `CandID` and the visit label corresponding to the
`SessionID` given as input.

INPUT: the session ID to use to look for `CandID` and visit label

RETURNS: the candidate's `CandID` and the session visit label

### check\_if\_deface\_files\_already\_in\_db($session\_files, $session\_id)

Checks whether there are already defaced images present in the database for
the session.

INPUTS:
  - $session\_files: list of files to deface
  - $session\_id   : the session ID to use to look for defaced images in `files`

RETURNS: 1 if there are defaced images found, 0 otherwise

### grep\_t1\_ref\_file($session\_files, $ref\_t1\_scan\_type)

Grep the first t1w image from `$session_files` to use it as a reference image for
`deface_minipipe.pl`.

INPUTS:
  - $session\_files   : list of files to deface
  - $ref\_t1\_scan\_type: LORIS scan type of the t1w file to use as a reference
                       for `deface_minipipe.pl`

RETURNS: hash with information for the reference t1w image

### determine\_output\_dir\_and\_basename($root\_dir, $candID, $visit, $ref\_file)

Determine the output directory path and basename to be used by `deface_minipipe.pl`.

INPUTS:
  - $root\_dir: root directory (usually a temporary directory where defaced outputs
               will be created)
  - $candID  : candidate's `CandID`
  - $visit   : candidate's visit label
  - $ref\_file: hash with information about the reference t1 file to use to deface

RETURNS:
  - $output\_basedir : output base `CandID/VisitLabel` directory where defaced images
                      will be created
  - $output\_basename: basename to be used to create the `_deface_grid_0.mnc` file

### deface\_session($ref\_file, $session\_files, $output\_basename)

Function that will run `deface_minipipe.pl` on all anatomical images of the session
and will return all defaced outputs in a hash.

INPUTS:
  - $ref\_file       : hash with info about the reference t1w file used to deface
  - $session\_files  : list of other files than the reference t1w file to deface
  - $output\_basename: output basename to be used by `deface_minipipe.pl`

RETURNS: hash of defaced images with relevant information necessary to register them

### fetch\_defaced\_files($ref\_file, $session\_files, $output\_basename)

Function that will determine the name of the defaced outputs and check that the
defaced outputs indeed exists in the file system. If all files are found in the
filesystem, it will return a hash with all information necessary for registration
of the defaced image.

INPUTS:
  - $ref\_file       : hash with info about the reference t1w file used to deface
  - $session\_files  : list of other files than the reference t1w file to deface
  - $output\_basename: output basename to be used by `deface_minipipe.pl`

RETURNS: hash of defaced images with relevant information necessary to register them

### register\_defaced\_files($defaced\_images)

Registers the defaced images using `register_processed_data.pl`.

INPUT: hash with the defaced images storing their input FileID and scan type

### create\_defaced\_scan\_type($scan\_type)

Function that inserts a new scan type in `mri_scan_type` if the scan type does not
already exists in `mri_scan_type`.

INPUT: the scan type to look for or insert in the `mri_scan_type` table

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

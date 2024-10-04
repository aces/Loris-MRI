# NAME

minc\_to\_bids\_converter.pl -- a script that creates a BIDS compliant imaging
dataset from the MINC files present in the `assembly/` directory.

# SYNOPSIS

perl tools/minc\_to\_bids\_converter.pl `[options]`

Available options are:
\-profile             : name of the config file in `../dicom-archive/.loris_mri`
\-tarchive\_id         : The ID of the DICOM archive to be converted into a BIDS
                       dataset (optional, if not set, convert all DICOM archives)
\-dataset\_name        : Name/Description of the dataset to be generated in BIDS
                       format; for example BIDS\_First\_Sample\_Data. The BIDS data
                       will be stored in a directory with that `dataset_name`
                       under the `BIDS_export` directory.
\-slice\_order\_philips : Philips scanners do not have the `SliceOrder` in their
                       DICOM headers so it needs to be provided an argument to
                       this script. `ascending` or `descending` are expected.
                       If slice order is `interleaved`, then it needs to be logged
                       in the JSON as `Not Supplied`
\-verbose             : if set, be verbose

# DESCRIPTION

This \*\*BETA\*\* version script will create a BIDS compliant NIfTI file structure of
the MINC files currently present in the `assembly` directory. If the argument
`tarchive_id` is specified, only the images from that tarchive will be processed.
Otherwise, all `tarchive_id`'s present in the `tarchive` table will be processed.

Before running the script, make sure that:
  - the "MINC to BIDS Converter Tool Options" section of the Configuration module has been updated.
    Note: the "BIDS Validation options to ignore" field is optional. It needs to be used in case
    there are some known checks performed by the bids-validator that are known to fail. Complete
    list of error code for the bids-validator can be found at the following link:
    https://github.com/bids-standard/bids-validator/blob/master/bids-validator/utils/issues/list.js
  - the tables `bids_category`, `bids_scan_type_subcategory`, `bids_scan_type` and
    `bids_mri_scan_type_rel` have been populated and customized as per the project's
    acquisition protocols

Keep the following restrictions/expectations in mind when populating the above database tables:
  - The `bids_category` table will house the different imaging "categories" which a
    default install would set to `anat`, `func`, `dwi`, and `fmap`. More entries
    can be added as more imaging categories are supported by the BIDS standards.
  - The `bids_scan_type` table will house the different "BIDS scan types" which a
    default install would set to `T1w`, `T2w`, `FLAIR`, `bold`, `dwi`
  - The `bids_scan_type_subcategory` table will house the different sub-categories
    used by BIDS to describe a scan type. For example, resting-state fMRI and memory
    task fMRI scan types would have the following `BIDSScanTypeSubCategoryName`: a
    hyphen concatenated string, with the first part describing the BIDS imaging
    sub-category, "task" as an example here, and the second describing this sub-category,
    "rest" or "memory" as an example. Note that the second part after the hyphen is
    used in the JSON file for the header "TaskName"
  - Multi-echo sequences would be expected to see their `BIDSMultiEcho` column of the
    `bids_mri_scan_type_rel` table filled with "echo-1", "echo-2", etc...

Filling out these values properly as outlined in this description is mandatory as these
values will be used to rename the NIfTI file, as per the BIDS requirements.

## METHODS

### getFileList($db\_handle, $givenTarchiveID)

Gets the list of MINC files associated to a given TarchiveID.

INPUTS:
    - $db\_handle        : database handle
    - $given\_tarchive\_id: the `TarchiveID` under consideration

RETURNS:
    - %file\_list: hash with files and their information for a given `TarchiveID`

    {
        "1" => {
            'fileID'        => 'FileID value',
            'file'          => 'file path',
            'echoTime'      => 'Echo Time of the file',
            'MriScanTypeID' => 'Scan type ID',
            'candID'        => 'Candidate CandID',
            'sessionID'     => 'Session ID',
            'visitLabel'    => 'Visit Label',
            'echoNumber'    => 'Echo Number of the scan',
            'seriesNumber'  => 'Series Number of the scan',
            'imageType'     => 'Image Type',
            'lorisScanType' => 'LORIS Scan Type name'
        },
        "2" => {
            'fileID'        => 'FileID value',
            'file'          => 'file path',
            'echoTime'      => 'Echo Time of the file',
            'MriScanTypeID' => 'Scan type ID',
            'candID'        => 'Candidate CandID',
            'sessionID'     => 'Session ID',
            'visitLabel'    => 'Visit Label',
            'echoNumber'    => 'Echo Number of the scan',
            'seriesNumber'  => 'Series Number of the scan',
            'imageType'     => 'Image Type',
            'lorisScanType' => 'LORIS Scan Type name'
        }
        ...
    }

### getParameterTypeID($db\_handle, $parameter\_type\_name)

Greps the ParameterTypeID value for a given parameter type.

INPUTS:
    - $db\_handle          : database handle
    - $parameter\_type\_name: name of the parameter type to query

OUTPUT:
    - ParameterTypeID found for the parameter type

### determine\_run\_number(%file\_list)

Determines the run number to associate with the scan and adds it to the
%file\_list hash information for a given file.

Note: the run number is determined based on the seriesNumber field of the
session since the MINC number might not always have been attributed
sequentially when running the insertion pipeline.

INPUT:
    - %file\_list: hash with images information associated with a tarchive

### makeNIIAndHeader($db\_handle, %file\_list)

This function converts the MINC files into NIfTI files that will be organized
in a BIDS structure.
It also creates a .json file for each NIfTI file by getting the header values
from the `parameter_file` table. Header information is selected based on the
BIDS document
([BIDS specifications](http://bids.neuroimaging.io/bids_spec1.0.2.pdf); page
14 through 17).

INPUTS:
    - $db\_handle: database handle
    - %file\_list: hash with files' information.

OUTPUT:
    - %phasediff\_seriesnb\_hash: hash containing information regarding which
                                fieldmap should be associated to which
                                functional or DWI scan to be added in the
                                sidecar JSON file of the fieldmaps.

### grep\_bids\_scan\_categories\_from\_db($db\_handle, $acq\_protocol\_id)

Queries the bids tables in conjunction with the scan type table to
obtain the mapping between the acquisition protocol of the MINC files
and the BIDS scan labelling scheme to be used.

INPUT:
    - $db\_handle      : database handle
    - $acq\_protocol\_id: acquisition protocol ID of the MINC file

OUTPUT:
    - $rowhr: hash with the BIDS scan type information.

    {
        'MRIScanTypeID'           => 'acquisition protocol ID of the MINC file',
        'BIDSCategoryName'        => 'BIDS category to use for the NIfTI file, aka anat, func, fmap, dwi...',
        'BIDSScanTypeSubCategory' => 'BIDS subcategory to use for the NIfTI file, aka task-rest, task-memory...',
        'BIDSEchoNumber'          => 'Echo Number associated with the NIfTI file',
        'ScanType'                => 'label of the LORIS Scan type from the mri_scan_type table'
    }

Note: BIDSEchoNumber and BIDSScanTypeSubCategory can be null for a given NIfTI file.

### create\_nifti\_bids\_file($data\_basedir, $minc\_path, $bids\_dir, $nifti\_name, $file\_id, $modality\_type)

Convert the MINC file into a NIfTI file labelled and organized according to the BIDS specifications.

INPUTS:
    - $data\_basedir : base data directory (where the assembly and BIDS\_export directories are located)
    - $minc\_path    : relative path to the MINC file
    - $bids\_dir     : relative path to the BIDS directory where the NIfTI file should be created
    - $nifti\_name   : name to give to the NIfTI file
    - $file\_id      : FileID of the MINC file in the files table
    - $modality\_type: BIDS modality type or category (a.k.a. 'anat', 'func', 'fmap'...)

OUTPUT:
    - relative path to the created NIfTI file

### determine\_bids\_nifti\_file\_name($minc\_file\_hash, $bids\_label\_hash, $run\_nb, $echo\_nb)

Determines the BIDS NIfTI file name to be used when converting the MINC file into a BIDS
compatible NIfTI file.

INPUTS:
    - $minc\_file\_hash : hash with candidate, visit label & scan type information associated with the MINC file
    - $bids\_label\_hash: hash with the BIDS labelling information corresponding to the MINC file's scan type.
    - $run\_nb         : run number to use to label the NIfTI file to be created
    - $mag\_echo\_nb    : echo number to use to label the NIfTI file to be created (can be undefined)

OUTPUT:
    - $nifti\_name: name of the NIfTI file that will be created

### add\_entry\_in\_participants\_bids\_file($minc\_file\_hash, $bids\_root\_dir, $db\_handle)

Adds an entry in the participants.tsv BIDS file for a given candidate.

INPUTS:
    - $minc\_file\_hash: hash with information associated to the MINC file
    - $bids\_root\_dir : path to the BIDS root directory
    - $db\_handle     : database handle

### grep\_participants\_values\_from\_db($db\_handle, $cand\_id)

Gets participant's sex from the candidate table.

INPUTS:
    - $db\_handle: database handle
    - $cand\_id  : candidate ID

OUTPUT:
    - @values: array with values returned from the candidate table

### create\_participants\_tsv\_and\_json\_file($participants\_tsv\_file, $participants\_json\_file)

Creates the BIDS participants.tsv and participants.json files in the root directory of the
BIDS structure. Note: the TSV file will only contain participant\_id and sex information.

INPUTS:
    - $participants\_tsv\_file : BIDS participants TSV file
    - $participants\_json\_file: BIDS participants JSON file

### add\_entry\_in\_scans\_tsv\_bids\_file($minc\_file\_hash, $bids\_root\_dir, $nifti\_full\_path, $session\_id, $db\_handle)

Adds an entry in the session level BIDS scans.tsv file.

INPUTS:
    - $minc\_file\_hash : hash with information about the MINC file
    - $bids\_root\_dir  : BIDS root directory path
    - $nifti\_full\_path: full path to the BIDS NIfTI file to add in the TSV file
    - $session\_id     : session ID in the session table
    - $db\_handle      : database handle

### create\_scans\_tsv\_and\_json\_file($scans\_tsv\_file, $scans\_json\_file)

Creates the BIDS session level scans.tsv and scans.json files of the BIDS structure.
Note: the TSV file will only contain filename and candidate\_age\_at\_acquisition information for now.

INPUTS:
    - $scans\_tsv\_file : BIDS session level scans TSV file
    - $scans\_json\_file: BIDS session level scans JSON file

### grep\_age\_values\_from\_db($db\_handle, $cand\_id, $visit\_label, $filename\_entry)

Gets the age of the candidate at the time of the acquisition from the session table.

INPUTS:
    - $db\_handle     : database handle
    - $cand\_id       : candidate ID
    - $visit\_label   : visit label
    - $filename\_entry: filename to be associated with the age found

OUTPUT:
    - @values: values associated with that filename

### determine\_BIDS\_scan\_JSON\_file\_path($nifti\_name, $bids\_scan\_directory)

Determines the path of the JSON file accompanying the BIDS NIfTI file.

INPUTS:
    - $nifti\_name         : name of the NIfTI file for which the JSON name needs to be determined
    - $bids\_scan\_directory: BIDS directory where the NIfTI and JSON files for the scan will go

OUTPUTS:
    - $json\_filename: file name of the BIDS JSON side car file
    - $json\_fullpath: full path of the BIDS JSON side car file

### write\_BIDS\_JSON\_file($json\_fullpath, $header\_hash)

Write a BIDS JSON file based on the content of $header\_hash.

INPUTS:
    - $json\_fullpath: full path to the JSON file to create
    - $header\_hash  : hash with the information to print into the JSON file

### write\_BIDS\_TEXT\_file($filename, $content)

Write the content stored in $content into a given text file.

INPUTS:
    - $file\_path: path to the file to write
    - $content  : content to be written in the text file

### create\_DWI\_bval\_bvec\_files($bids\_scan\_directory, $nifti\_file\_name, $file\_id)

Creates BVAL and BVEC files associated to a DWI scan.

INPUTS:
    - $bids\_scan\_directory: directory where the BVAL and BVEC files should be created
    - $nifti\_file\_name    : name of the NIfTI file for which BVAL and BVEC files need to be created
    - $file\_id            : file ID of the DWI scan from the files table

### gather\_parameters\_for\_BIDS\_JSON\_file($minc\_full\_path, $json\_filename, $bids\_categories\_hash)

Gathers the scan parameters to add into the BIDS JSON side car file.

INPUTS:
    - $minc\_full\_path      : full path to the MINC file with header information
    - $json\_filename       : name of the BIDS side car JSON file where scan parameters will go
    - $bids\_categories\_hash: hash with the BIDS categories information

OUTPUT:
    - $header\_hash: hash with the header information to insert into the BIDS JSON side car file

### grep\_generic\_header\_info\_for\_JSON\_file($minc\_full\_path, $json\_filename)

Greps generic header information that applies to all scan types and map them to the BIDS ontology.

INPUTS:
    - $minc\_full\_path: full path to the MINC file
    - $json\_filename : name of the BIDS JSON side car file

OUTPUT:
    - %header\_hash: hash with scan's header information

### add\_EffectiveEchoSpacing\_and\_TotalReadoutTime\_info\_for\_JSON\_file($header\_hash, $minc\_full\_path)

Logic to determine the EffectiveEchoSpacing and TotalReadoutTime parameters for functional, ASL and DWI
acquisitions.

INPUTS:
    - $header\_hash   : hash with scan parameters that will be update with EffectiveEchoSpacing & TotalReadoutTime
    - $minc\_full\_path: full path to the MINC file

### add\_RepetitionTimeExcitation\_info\_for\_JSON\_file($header\_hash, $minc\_full\_path)

Get the RepetitionTimeExcitation parameter from the MINC header for MP2RAGE, T1map and UNIT1.

INPUTS:
    - $header\_hash   : hash with scan parameters that will be update with RepetitionTimeExcitation
    - $minc\_full\_path: full path to the MINC file

### grep\_SliceOrder\_info\_for\_JSON\_file($header\_hash, $minc\_full\_path, $manufacturer\_philips)

Logic to determine the SliceOrder scan parameter for the BIDS JSON side car file.

INPUTS:
    - $header\_hash          : hash with scan parameters that will be update with SliceOrder
    - $minc\_full\_path       : full path to the MINC file
    - $manufacturer\_phillips: boolean stating whether the scanner is a Phillips device

### grep\_TaskName\_info\_for\_JSON\_file($bids\_categories\_hash, $header\_hash)

Greps the TaskName information derived from the BIDSScanTypeSubCategory for the BIDS JSON side car file.

INPUTS:
    - $bids\_categories\_hash: hash with BIDS category and sub category information
    - $header\_hash: hash with scan parameters that will be update with TaskName

### grep\_phasediff\_associated\_magnitude\_files($loris\_files\_list, $phasediff\_loris\_hash, $db\_handle)

Greps the magnitudes files associated with a given phasediff fieldmap scan file.

INPUTS:
    - $loris\_files\_list    : list of files extracted from LORIS for a given Tarchive
    - $phasediff\_loris\_hash: hash with phasediff fieldmap file information
    - $db\_handle           : database handle

OUTPUT:
    - %magnitude\_files: hash magnitude files associated to the phasediff fieldmap file

    {
        'Echo1' => 'magnitude file with echo number 1',
        'Echo2' => 'magnitude file with echo number 2'
    }

### grep\_acquisitionProtocolID\_from\_BIDS\_scan\_type($db\_handle, $bids\_scan\_type)

Greps the MriScanTypeID associated to a BIDS magnitude file in the database.

INPUTS:
    - $db\_handle     : database handle
    - $bids\_scan\_type: name of the BIDS scan type (for example: magnitude)

OUTPUT:
    - MriScanTypeID associated to the BIDS scan type file in the database

### create\_BIDS\_magnitude\_files($phasediff\_filename, $magnitude\_files\_hash)

Creates the BIDS magnitude files of fieldmap acquisitions.

INPUTS:
    - $phasediff\_filename  : name of the BIDS fieldmap phasediff file
    - $magnitude\_files\_hash: hash with fieldmap associated magnitude files information

### updateFieldmapIntendedFor($file\_hash, $phasediff\_list)

Updates the FieldmapIntendedFor field in the JSON side car with the list of
filenames the fieldmap should be applied on.

INPUTS:
    - $file\_hash     : hash with all the files information
    - $phasediff\_list: list of fieldmap phasediff files

### updateJSONfileWithIntendedFor($json\_filepath, $intended\_for)

Updates the IntendedFor header in the BIDS JSON file of a fieldmap acquisition.

INPUTS:
    - $json\_filepath: path to the JSON file to update
    - $intended\_for : list of file names to add to the IntendedFor JSON parameter

### getClosestNumberInArray($val, $arr)

Get the closest number to $val in an array.

INPUTS:
    - $val: value
    - $arr: array

OUTPUT:
    - the closest number to $val in array $arr

### registerBidsFileInDatabase($file\_path, $file\_level, $file\_type, $file\_id, $modality\_type, $behavioural\_type, session\_id)

Registers the created BIDS files into the table bids\_export\_files with links to the FileID from the files table.

INPUTS:
    - $file\_path       : path to the BIDS file to insert in the bids\_export\_files table
    - $file\_level      : BIDS file level. One of 'study', 'image' or 'session'
    - $file\_type       : BIDS file type. One of 'json', 'README', 'tsv', 'nii', 'bval', 'bvec', 'txt'
    - $file\_id         : FileID of the associated MINC file from the files table
    - $modality\_type   : BIDS modality of the file. One of 'fmap', 'asl', 'anat', 'dwi', 'func'.
                         'NULL' if the BIDS file to insert is not an acquisition file.
    - $behavioural\_type: non-acquisition BIDS files type. One of 'dataset\_description', 'README',
                         'bids-validator-config', 'participants\_list\_file', 'session\_list\_of\_scans'.
                         'NULL' if the BIDS file to insert is an acquisition file.
    - $session\_id      : session ID associated to the file to insert. 'NULL' if the file is at the BIDS study level

### get\_BIDSNonImgFileCategoryID($category\_name)

Get the BIDSNonImgFileCategoryID from the bids\_export\_non\_imaging\_file\_category table for a category name.

INPUTS:
  - $category\_name: name of the non-imaging file category to look for

OUTPUT: BIDS non-imaging file category ID or undef

### get\_BIDSCategoryID($category\_name)

Get the BIDSCategoryID from the bids\_category table for a category name.

INPUTS:
  - $category\_name: name of the non-imaging file category to look for

OUTPUT: BIDS category ID or undef

### get\_BIDSExportFileLevelCategoryID($level\_name)

Get the BIDSExportFileLevelCategoryID from the bids\_export\_file\_level\_category table for a level name.

INPUTS:
  - $level\_name: name of the BIDS export file level category to look for

OUTPUT: BIDS export file level category ID or undef

# TO DO

    - Make the SliceOrder, which is currently an argument at the command line,
    more robust (such as making it adaptable across manufacturers that might not
    have this header present in the DICOMs, not just Philips like is currently the
    case in this script. In addition, this variable can/should be defined on a site
    per site basis.
    - Need to add to the multi-echo sequences a JSON file with the echo time within,
    as well as the originator NIfTI parent file. In addition, we need to check from
    the database if the sequence is indeed a multi-echo and require the
    C<BIDSMultiEcho> column set by the project in the C<bids_mri_scan_type_rel>
    table.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

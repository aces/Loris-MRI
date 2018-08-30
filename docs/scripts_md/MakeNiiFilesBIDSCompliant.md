# NAME

MakeNIIFilesBIDSCompliant.pl -- a script that creates a BIDS compliant imaging
dataset from the MINCs in the `assembly/` directory

# SYNOPSIS

perl tools/MakeNIIFilesBIDSCompliant.pl `[options]`

Available options are:

\-profile                : name of the config file in `../dicom-archive/.loris_mri`

\-tarchive\_id            : The ID of the DICOM archive to be converted into BIDS
                        dataset (optional, if not set, convert all DICOM archives)

\-dataaset\_name          : Name/Description of the dataset about to be generated
                        in BIDS format; for example BIDS\_First\_Sample\_Data. The
                        BIDS data will be stored in a directory called the `dataset_name`

\-slice\_order\_philips    : Philips scanners do not have the `SliceOrder` in their
                        DICOMs so provide it as an argument; `ascending` or
                        `descending` is expected; otherwise, it will be logged
                        in the JSON as `Not Supplied`"

\-verbose                : if set, be verbose

# DESCRIPTION

This \*\*BETA\*\* version script will create a BIDS compliant NIfTI file structure of
the MINC files currently present in the \`assembly\` directory. If the argument
\`tarchive\_id\` is specified, only the images from that archive will be processed.
Otherwise, all files in \`assembly\` will be included in the BIDS structure,
while looping though all the 'tarchive\_id\`'s in the 'tarchive\` table.

Running this script requires JSON library for Perl.
Run \`sudo apt-get install libjson-perl\` to get it.

## Methods

### getFileList($dbh, $dataDir, $givenTarchiveID)

This function will grep all the `TarchiveID` and associated `ArchiveLocation`
present in the `tarchive` table and will create a hash of this information
including new `ArchiveLocation` to be inserted into the database.

INPUTS:
    - $dbh             : database handler
    - $dataDir         : where the imaging files are located
    - $givenTarchiveID : the `TarchiveID` under consideration

RETURNS:
    - %file\_list       : hash with files for a given `TarchiveID`

### makeNIIAndHeader($dbh, %file\_list)

This function will make NIfTI files out of the MINC files and puts them in BIDS
format.
It also creates a .json file for each NIfTI file by getting the header values
from the `parameter_file` table. Header information is selected based on the
BIDS document (http://bids.neuroimaging.io/bids\_spec1.0.2.pdf;
pages 14 through 17).

INPUTS:
    - $dbh          : database handler
    - $file\_list    : hash with files' information.

### fetchBVAL\_BVEC($dbh, $bvFile, $fileID, $destDirFinal, @headerNameBVECDBArr)

This function will create `bval` and `bvec` files from a DWI input file, in a
BIDS compliant manner. The values (bval OR bvec) will be fetched from the
database `parameter_file` table.

INPUTS:
    - $dbh                  : database handler
    - $bvfile               : bval or bvec filename
    - $nifti                : original NIfTI file
    - $fileID               : ID of the file from the `files` table
    - $destDirFinal         : final directory destination for the file to be
                              generated
    - @headerNameBVECDBArr  : array for the names of the database parameter to
                              be fetched (bvalues for bval and x, y, z direction
                              for bvec)

### fetchMincHeader($file,$field)

This function parses the MINC header and looks for specific field's value.
\*\*This is a modified version of the function from register\_processed\_data.pl\*\*

INPUTS:
  - $file : MINC file to get header value from
  - $field: header to fetch value from

RETURNS:
  - $value : header value from C$field>

# TO DO

\- Make the SliceOrder, which is currently an argument at the command line,
more robust (such as making it adaptable across manufacturers that might not
have this header present in the DICOMs, not just Philips like is currently the
case in this script. In addition, this variable can/should be defined on a site
per site basis.
\- Need to add to the multi-echo sequences a JSON file with the echo time within,
as well as the originator NIfTI parent file. In addition, we need to check from
the database if the sequence is indeed a multi-echo and require the
`BIDSMultiEcho` column set by the project in the `BIDS_mri_scan_type_rel`
table.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

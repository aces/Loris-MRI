# NAME

DICOM::DCMSUM -- Archives DICOM summaries

# SYNOPSIS

# DESCRIPTION

Deals with DICOM summaries for archiving and other purposes.

## Methods

### new($dcm\_dir, $tmp\_dir) >> (constructor)

Creates a new instance of this class.

INPUTS:
  - $dcm\_dir: DICOM directory
  - $tmp\_dir: target location

RETURNS: a `DICOM::DCMSUM` object

### database($dbh, $meta, $update, $tarType, $tarLog, $DCMmd5, $Archivemd5, $Archive, $neurodbCenterName)

Inserts or updates the `tarchive` tables.

INPUTS:
  - $dbh              : database handle
  - $meta             : name of the .meta file
  - $update           : set to 1 to update `tarchive` entry, 0 otherwise
  - $tarType          : tar type version
  - $tarLog           : name of the .log file
  - $DCMmd5           : DICOM MD5SUM
  - $Archivemd5       : DICOM archive MD5 sum
  - $Archive          : archive location
  - $neurodbCenterName: center name

RETURNS: 1 on success

### is\_study\_unique($dbh, $update, $Archivemd5)

Verifies if the DICOM study is already registered in the `tarchive` table
using the `StudyUID` field of the DICOM files. If the study is already present in the
`tarchive` tables but `-clobber` was not when running `dicomTar.pl` or that we are
using `dicomSummary.pl`, it will return the appropriate error message.

INPUTS:
  - $dbh       : database handle
  - $update    : set to 1 to update `tarchive` entry, 0 otherwise
  - $Archivemd5: DICOM archive MD5 sum

RETURNS:
  - $unique\_study: set to 0 if the study was found in the database, 1 otherwise
  - $message     : error message or undef if no error found

### read\_file($file)

Reads the content of a file (typically .meta file in the DICOM archive).

INPUT: the file to be read

RETURNS: the content of the file

### acquistion\_count()

Figures out the total number of acquisitions.

RETURNS: number of acquisitions

### file\_count()

Figures out the total number of files.

RETURNS: number of files

### dcm\_count()

Figures out the total number of DICOM files.

RETURNS: number of DICOM files, or exits if no DICOM file found.

### acquisition\_AoH($self->{dcminfo})

Creates an Array of Hashes (AoH) describing acquisition parameters for each
file.

INPUT: list of DICOM files

RETURNS: array of hashes with acquisition parameters for each file

### collapse($self->{acqu\_AoH})

Collapses the AoH to get a summary of acquisitions.

INPUT: array of hashes with acquisition parameters for each DICOM file

RETURNS: hash table acquisition summary collapsed by unique acquisition
definitions

### acquisitions(self->{acqu\_Sum})

Sorts the Array of Hash by acquisition number.

INPUT: array of hash table acquisition summary

RETURNS: acquisition listing sorted by acquisition number to be used for summary

### content\_list($dcmdir)

Gets DICOM info from all files in a directory.

Note: The -k5 was added on August 28th 2006 because the guys in Kupio assign
duplicate FN SN EN values for scouts and subsequent scans.

INPUT: DICOM directory

RETURNS: sorted DICOM information from all the files in the DICOM directory

### read\_dicom\_data($file)

Gets DICOM info from a DICOM file.

INPUT: DICOM file to read

RETURNS: array with pertinent DICOM information read from the DICOM file

### fill\_header()

Fills header information reading the first valid DICOM file.

RETURNS: header information

### confirm\_single\_study()

Confirms that only one DICOM study is in the DICOM directory to be archived.
Returns `False` if there is more than one `StudyUID`, otherwise it returns
that `StudyUID`.

RETURNS: `StudyUID` found in the DICOM directory, or `false` if more than one
study was found

### print\_header()

Prints HEADER using the format defined in `&format_head` function.

### format\_head()

Format definition to print the head of the HEADER.

### print\_content()

Prints the CONTENT using formats defined in `&write_content_head`.

### write\_content\_head()

Prints the Content head.

### write\_dcm($dcm)

Prints all DICOM files.

INPUT: array of DICOM information to print

### write\_other($dcm)

Prints all other files.

INPUT: array of other files information

### print\_acquisitions()

Prints Acquisitions using formats from `&write_acqu_head` and
`&write_acqu_content`

### write\_acqu\_head()

Prints acquisition table header.

### write\_acqu\_content($acqu)

Prints acquisition's content.

INPUT: array of acquisition information to print

### print\_footer()

Prints footer using formats from `&write_footer`.

### write\_footer()

Prints footer summary information.

### dcmsummary()

Prints the whole thing using `&print_header`, `&print_content`,
`&print_acquisitions` and `&print_footer`. This is what you really want.

**Unrelated but useful functions**

### trimwhitespace($string)

Gets rid of nasty whitespace

INPUT: string to remove white space

RETURNS: string without white space

### date\_format($first, $second)

If only one date argument is provided, then it will convert YYYYMMDD date
format into YYYY-MM-DD.
If two date arguments are provided, then it will compute the difference in
decimal and Y M +/- Days.

INPUTS: date to format, (optionally, a second date to get the difference
between two dates)

RETURNS: formatted date, or the different between two dates

### md5sum($filename)

Computes the MD5 sum of a file and outputs a format similar to `md5sum` on
Linux.

INPUT: file name to use to compute MD5 sum

RETURNS: MD5 sum of the file

# TO DO

Fix comments written as #fixme in the code.

# LICENSING

Copyright (c) 2006 by J-Sebastian Muehlboeck, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

# AUTHORS

J-Sebastian Muehlboeck,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

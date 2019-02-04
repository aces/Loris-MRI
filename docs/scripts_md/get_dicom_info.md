# NAME

get\_dicom\_info.pl -- reads information out of the DICOM file headers

# SYNOPSIS

perl get\_dicom\_info.pl \[options\] &lt;dicomfile> \[&lt;dicomfile> ...\]

Available options are:

\-image    : print image number

\-exam     : print exam number

\-studyuid : print study UID

\-series   : print series number

\-echo: print echo number

\-width: print width

\-height: print height

\-slicepos: print slice position

\-slice\_thickness: print slice thickness

\-tr                : print repetition time (TR)

\-te                : print echo time (TE)

\-ti                : print inversion time (TI)

\-date              : print acquisition date

\-time              : print acquisition time

\-file              : print file name

\-pname             : print patient name

\-pdob              : print patient date of birth

\-pid               : print patient ID

\-institution       : print institution name

\-series\_description: print series description

\-sequence\_name     : print sequence name

\-scanner           : print scanner

\-attvalue          : print the value(s) of the specified attribute

\-stdin             : use STDIN for the list of DICOM files

\-labels            : print one line of labels before the rest of the output

\-error\_string      : string to use for reporting empty fields

\-verbose                : Be verbose if set

\-version                : Print CVS version number and exit

# DESCRIPTION

A tool to read information out of the DICOM file headers.

## Methods

### cleanup\_and\_die($message, $status)

Subroutine to clean up files and exit.

INPUTS:
  - $message: message to be printed in STDERR
  - $status : status code to use to exit the script

### get\_dircos()

Subroutine to get a direction cosine from a vector, correcting for
magnitude and direction if needed (the direction cosine should point
along the positive direction of the nearest axis).

RETURNS: X, Y and Z cosines

### convert\_coordinates(@coords)

Routine that multiplies X and Y world coordinates by -1.

INPUT: array with world coordinates

RETURNS: array with converted coordinates

### vector\_dot\_product($vec1, $vec2)

Routine to compute the dot product of two vectors.

INPUTS:
  - $vec1: vector 1
  - $vec2: vector 2

RESULTS: result of the dot product

### vector\_cross\_product($vec1, $vec2)

Routine to compute a vector cross product

INPUTS:
  - $vec1: vector 1
  - $vec2: vector 2

RESULTS: result of the vector cross product

### trim($input)

Remove leading and trailing spaces from the $input variable

INPUT: string to remove leading and trailing spaces from

RETURNS: string without leading and trailing spaces

### showcroft()

Accessor for field `@croft`.

### split\_dicom\_list($dlist)

Routine to split a DICOM list of values into a perl array using `\\`.

INPUT: list of DICOM values

RETURNS: array of DICOM values if multiple values or DICOM value if only one value

### SetupArgTables()

To set up the arguments to the GetOpt table.

RETURNS: an array with all the options of the script

### InfoOption(@addr)

Greps the group and element information from the GetOpt table options specified.

INPUTS:
  - $option: name of the option
  - $rest  : reference to the remaining arguments of the command line
  - @addr  : array reference with DICOM group & element from the GetOpt option

### TwoArgInfoOption($option, $rest)

Greps the group and element information from the GetOpt table options specified
and checks that the two arguments required by the option have been set.

INPUTS:
  - $option: name of the option that requires two arguments
  - $rest  : array with group and element information from the GetOpt table

### CreateInfoText()

Creates the information text to be displayed by GetOpt to describe the script/

# LICENSING

License: GPLv3

# AUTHORS

Jonathan Harlap,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

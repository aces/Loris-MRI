# NAME

DICOM::Element -- Element routines for DICOM::DICOM module

# SYNOPSIS

use DICOM::Element;

# DESCRIPTION

Element routines for DICOM::DICOM module to read DICOM headers.

Each element is a hash with the following keys:
  group	    Group (hex).
  element	Element within group (hex).
  offset	Offset from file start (dec).
  code	    Field code eg 'US', 'UI'.
  length	Field value length (dec).
  name	    Field descriptive name.
  value	    Value.
  header	All bytes up to value, for easy writing.

## Methods

### new() (constructor)

Creates a new instance of this class.

RETURNS: a DICOM::Element object

### fill($IN, $dictref, $big\_endian\_image)

Fills in self from file.

INPUT: input file, DICOM dictionary, big endian image

RETURNS: element hash

### readInt($IN, $bytes, $len).

Reads int variables. ??????????????????????????

INPUT:
  $IN   : input file stream.
  $bytes: SHORT (2) or INT (4) bytes.
  $len  : total number of bytes in the field.

If fieldlength > bytelength, multiple values are read in and stored as a
string representation of an array.

RETURNS: string representation of an array???

### writeInt($OUT, $bytes)

Writes Int variable into the output file `$OUT`. ?????

INPUT: output file, number of bytes in the field

### readFloat($IN, $format, $len)

Reads float variables ????

INPUT: input file stream, format of the variable, total number of bytes in
the field.

RETURNS: string ?????

### readSequence($IN, $len)

Reads sequence. ??????

Three different cases:
    - implicit VR, explicit length
    - explicit VR, undefined length, items of defined length (w/end delimiter)
    - implicit VR, undefined length, items of undefined length

INPUT: input file stream, total number of bytes in the field

RETURNS: ??????

### readLength($IN)

Reads length. ????????????????????????
  - Implicit VR: Length is 4 byte int.
  - Explicit VR: 2 bytes hold VR, then 2 byte length.

INPUT: input file stream

RETURNS: the value field length, and length before value field

### values()

Returns the values of each field of the object.

RETURNS: values of each field

### print()

Prints formatted representation of element to stdout.

### valueString()

Returns a string representation of the value field.

RETURNS: string representation of the value field, or null if value field is
binary

Writes this data element to disk. All fields up to value are stored in
immutable field 'header' - write this to disk then value field.

INPUT: output file

### value()

Returns the value of the field.

RETURNS: value field

### setValue($value)

Sets the value field of this element. Truncates to max length.

INPUT: value field

### byteswap($valref)

?????

INPUT: value reference???

# TO DO

Better documentation of the following functions:
  - readInt()
  - readFloat()
  - readSequence($IN, $len)
  - readLength($IN)
  - writeInt($OUT, $bytes)
  - byteswap($valref)

# BUGS

None reported (or list of bugs)

# LICENSING

License: GPLv3

# AUTHORS

Andrew Crabb (ahc@jhu.edu),
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

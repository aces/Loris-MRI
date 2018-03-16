# NAME

DICOM::Element -- Element routines for DICOM::DICOM module

# SYNOPSIS

    use DICOM::Element;

# DESCRIPTION

Element routines for DICOM::DICOM module to read binary DICOM headers.

Each element is a hash with the following keys:
  - group  : group (hex)
  - element: element within group (hex)
  - offset : offset from file start (dec)
  - code   : field code eg 'US', 'UI'
  - length : field value length (dec)
  - name   : field descriptive name
  - value  : value
  - header : all bytes up to value, for easy writing

## Methods

### new() (constructor)

Creates a new instance of this class.

RETURNS: a `DICOM::Element` object

### fill($IN, $dictref, $big\_endian\_image)

Fills in `self` from file.

INPUTS:
  - $IN              : input file
  - $dictref         : DICOM dictionary
  - $big\_endian\_image: if big endian image

RETURNS: element hash

### readInt($IN, $bytes, $len).

Reads Int.

INPUTS:
  - $IN   : input file stream.
  - $bytes: SHORT (2) or INT (4) bytes.
  - $len  : total number of bytes in the field.

If `fieldlength` > `bytelength`, multiple values are read in and stored as a
string representation of an array.

RETURNS: string representation of an array

### writeInt($OUT, $bytes)

Writes Int into the output file `$OUT`.

INPUTS:
  - $OUT  : output file
  - $bytes: number of bytes in the field

### readFloat($IN, $format, $len)

Reads Float.

INPUTS:
  - $IN    : input file stream
  - $format: format of the variable
  - $len   : total number of bytes in the field

RETURNS: string

### readSequence($IN, $len)

Reads Sequence.

Three different cases:
    - implicit Value Representation (VR), explicit length
    - explicit VR, undefined length, items of defined length (w/end delimiter)
    - implicit VR, undefined length, items of undefined length

INPUTS:
  - $IN : input file stream
  - $len: total number of bytes in the field

RETURNS: 'skipped' string

### readLength($IN)

Reads length.
  - Implicit Value Representation (VR): Length is 4 byte int.
  - Explicit VR: 2 bytes hold VR, then 2 byte length.

INPUT: input file stream

RETURNS: the value field length, and length before value field

### values()

Returns the values of each field of the object.

RETURNS: values of each field

### print()

Prints formatted representation of element to `STDOUT`.

### valueString()

Returns a string representation of the value field.

RETURNS: string representation of the value field, or null if value field is
          binary

### write($OUTFILE)

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

Swaps byte.

INPUT: value reference

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

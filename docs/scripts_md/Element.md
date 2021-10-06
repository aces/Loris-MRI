# NAME

DICOM::Element -- Element routines for `DICOM::DICOM` module

# SYNOPSIS

    use DICOM::Element;

# DESCRIPTION

Element routines for `DICOM::DICOM` module to read binary DICOM headers.

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

### new() >> (constructor)

Creates a new instance of this class.

RETURNS: a `DICOM::Element` object

### fill($IN, $dictref)

Fills in `self` from file.

INPUTS:
  - $IN              : input file
  - $dictref         : DICOM dictionary

RETURNS: element hash

### readInt($IN, $bytes, $len).

Decodes one or more integers that were encoded as a string of bytes
(2 or 4 bytes per number) in the file whose handle is passed as argument.

INPUTS:
  - $IN   : input file stream.
  - $bytes: SHORT (2) or INT (4) bytes.
  - $len  : total number of bytes in the field.

If `fieldlength` > `bytelength`, multiple values are read in and stored as a
string representation of an array.

RETURNS: string representation of the array of decoded integers
          (e.g. '\[34, 65, 900\]')

### writeInt($OUT, $bytes)

Encodes each integer stored in string `$this-`{'value'}> as a 2 or 4 byte
string and writes them in a file

INPUTS:
  - $OUT  : output file
  - $bytes: number of bytes (2 for shorts 4 for integers) in the field

### readFloat($IN, $format, $len)

Decodes a floating point number that was encoded as a string of bytes in the
file whose handle is passed as argument.

INPUTS:
  - $IN    : input file stream
  - $format: format used when decoding (with Perl's `unpack`) the number:
              `f` for floats and `d` for doubles
  - $len   : total number of bytes in the field

RETURNS: string

### readSequence($IN, $len)

Skips over either a fixed number of bytes or over multiple sets of byte
sequences delimited with specific byte values. When doing the latter,
byte `0x00000000` is used to signal the end of the set of sequences.
The sequence of bytes read is always discarded.

Three different cases:
    - implicit Value Representation (VR), explicit length
    - explicit VR, undefined length, items of defined length (w/end delimiter)
    - implicit VR, undefined length, items of undefined length

INPUTS:
  - $IN : input file stream
  - $len: total number of bytes to skip, or 0 if all sequences should be
           skipped until the delimiter `0x00000000` is found

RETURNS: 'skipped' string

### readLength($IN)

Reads the length of a VR from a file, as an integer encoded on 16 or 32 bits.
  - Implicit Value Representation (VR): Length is 4 byte int.
  - Explicit VR: 2 bytes hold VR, then 2 byte length.

INPUT: input file stream

RETURNS: the VR code (string of length 2) and the length of the associated
          VR value

### values()

Returns the properties of a VR: group, element, offset, code, length, name and
value.

RETURNS: the properties of a VR: group, element, offset, code, length, name and
          value

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

# LICENSING

License: GPLv3

# AUTHORS

Andrew Crabb (ahc@jhu.edu),
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

# NAME

DICOM::DICOM -- Perl library that allows Perl programs to read the headers of
medical image files conforming to DICOM standards.

# SYNOPSIS

    use DICOM;

    my $dicom = DICOM->new();
    $dicom->fill($dicomFile);
    my $patientName = $dicom->value('0010', '0010');

# DESCRIPTION

DICOM (Digital Imaging and Communications in Medicine) is a standard
designed to allow medical image files to be transferred, stored and
viewed on different makes of computers. Perl is a multi-platform
language that excels at system tasks such as file manipulation. It's
easy to learn, particularly if you are familiar with C or the Unix
shells and utility programs.

This library provides the methods to read and parse a DICOM file, then
to recover the contents of each header element by their standard DICOM
group and element codes. Header element values can be edited (either
through the GUI or command line) and the modified file written back to
disk.

## Methods

### new() >> (constructor)

Creates a new instance of this class.

RETURNS: a `DICOM::DICOM` object

### processOpts($href)

Stores and process the command line options from hash ref.

INPUT: a hash reference

### fill($infile, $big\_endian\_image)

Fills in hash with header members from given file.

INPUTS:
  - $infile          : file
  - $big\_endian\_image: big endian image (optional)

RETURNS: 1 if duplication, 0 on success

### write($outfile)

Writes currently open file to given file name, or to current name if no new
name specified. All fields before value are written verbatim; value field
is stored as is (possibly edited).

INPUT: file to write into

### printContents($outfile)

Prints all elements, to disk if file handle supplied.

INPUT: file to print into

### contents()

Returns a sorted array of references to element arrays.

RETURNS: sorted array of references

### setIndex($val)

Sets field index to sort by.

INPUT: value

RETURNS: 1 if new index, else 0.

### getIndex()

Returns the sort index.

RETURNS: sort index

### value($gp, $el)

Returns value of the element at (group, element).

INPUTS:
  - $gp: group
  - $el: element

RETURNS: value of the element

### field($gp, $el, $fieldname)

Returns field of given index from element.

INPUTS:
  - $gp       : group
  - $el       : element
  - $fieldname: field index

RETURNS: field of given index from element

### editHeader($editstr)

Edit header value from string.
String format: 'gggg,eeee=newvalue' or 'fieldname=newvalue'.
  gggg, eeee = group, element (in hex);
  fieldname  = name of field from @dicom\_fields.

INPUT: string to edit

RETURNS: undef unless group and element are defined

### fieldByName($searchname)

Returns group and element number of field with given name.

INPUT: name of the field to search

RETURNS: group and element number of field

### setElementValue($gp, $el, $newvalue)

Replaces value of given element.

INPUTS:
  - $gp      : group
  - $el      : element
  - $newvalue: new value

### hexadecimally()

### sortByField()

Sort array of value by field.

RETURNS: sorted array

### loop()

Doesn't do anything in non-graphical case.

# SEE ALSO

The DICOM standard - http://medical.nema.org/

# TO DO

Add support for sequences (SQ) (currently being skipped)

Better documentation for:
  - setIndex()
  - hexadecimally() -- non public?
  - loop - doesn't do anything in non-graphical case. investigate if this
  function is used, if not, remove

# COPYRIGHT AND LICENSE

Copyright (C) 2002 by Andrew Crabb
Some parts are Copyright (C) 2003 by Jonathan Harlap

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6.0 or,
at your option, any later version of Perl 5 you may have available.

License: GPLv3

# AUTHORS

Andrew Crabb, &lt;ahc@jhu.edu>,
Jonathan Harlap, &lt;jharlap@bic.mni.mcgill.ca>,
LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

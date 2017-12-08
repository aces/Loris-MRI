# DICOM.pm
# Andrew Crabb (ahc@jhu.edu), May 2002.
# Jonathan Harlap (jharlap@bic.mni.mcgill.ca) 2003
# Perl module to read DICOM headers.
# TODO: add support for sequences (SQ) (currently being skipped)
# $Id: DICOM.pm 4 2007-12-11 20:21:51Z jharlap $

package DICOM;

use strict;
use vars qw($VERSION %dict);

use DICOM::Element;
use DICOM::Fields;	# Standard header definitions.
use DICOM::Private;	# Private or custom definitions.

$VERSION = sprintf "%d", q$Revision: 4 $ =~ /: (\d+)/;

# Class variables.
my $sortIndex;		# Field to sort by.
my %opts;		# Command line options.
my $isdicm;		# Set to 1 if DICM file; 0 if NEMA.
my $currentfile;	# Currently open file.
my $preamblebuff = 0;	# Store initial 0x80 bytes.

# Initialize dictionary only once.
# Read the contents of the DICOM dictionary into a hash by group and element.
# dicom_private is read after dicom_fields, so overrides common fields.
BEGIN {
  foreach my $line (@dicom_fields, @dicom_private) {
    next if ($line =~ /^\#/);
    my ($group, $elem, $code, $numa, $name) = split(/\s+/, $line);
    my @lst = ($code, $name);
    $dict{$group}{$elem} = [@lst];
  }
}

sub new {
  my $class = shift;

  my $elements = {};
  bless $elements, $class;
  $elements->setIndex(2);
  return $elements;
}

# Store and process the command line options from hash ref.

sub processOpts {
  my $this = shift;
  my ($href) = @_;
  my $outfile;
  %opts = %$href;

  foreach my $key (keys %opts) {
    ($key eq 's') and $this->setIndex($opts{$key});	# Sort.
    ($key eq 'm') and $this->editHeader($opts{$key});	# Modify header.
    ($key eq 'o') and $outfile = $opts{$key};
  }
  # 'Save As' option is processed last.
  $this->write($outfile) if (defined($outfile));
}

# Fill in hash with header members from given file.

sub fill {
  my ($this, $infile, $big_endian_image) = @_;

  my($buff);
  $currentfile = $infile;
  open(INFILE, $infile) or return 1;
  binmode(INFILE);

  # Test for NEMA or DICOM file.  
  # If DICM, store initial preamble and leave file ptr at 0x84.
  read(INFILE, $preamblebuff, 0x80);
  read(INFILE, $buff, 4);
  $isdicm = ($buff eq 'DICM');
  die("Error: $infile is byte swapped\n") if ($buff eq 'IDMC');
  seek(INFILE, 0x00, 0) unless ($isdicm);

  my $duplications;

  until (eof(INFILE)) {
    my $element = DICOM::Element->new();
    ($element->fill(\*INFILE, \%dict, $big_endian_image)) or return 1;
    my $gp = $element->{'group'};
    my $el = $element->{'element'};
    if($gp eq '0000' && $el eq '0000' && defined($this->{$gp}{$el})) {
	$duplications++;
	if($duplications > 10) {
	    close(INFILE);
	    return 1;
	}
    }
    $this->{$gp}{$el} = $element;
  }
  close(INFILE);
  return 0;
}

# Write currently open file to given file name, or to current name 
# if no new name specified.  All fields before value are written
# verbatim; value field is stored as is (possibly edited).

sub write {
  my ($this, $outfile) = @_;

  $outfile = $currentfile unless (defined($outfile));
  # Copy over file preamble.
  open(OUTFILE, ">$outfile") or return 1;
  print OUTFILE $preamblebuff if ($isdicm);
  # Ensure base class method called.
  $this->DICOM::printContents(\*OUTFILE);
  close(OUTFILE);
}

# Print all elements, to disk if file handle supplied.

sub printContents {
  my ($this, $OUTFILE) = @_;
  my %hash = %$this;
  my ($gpref, %gp, $el, %elem);

  foreach my $gpref (sort hexadecimally keys(%hash)) {
    %gp = %{$hash{$gpref}};
    foreach my $el (sort hexadecimally keys(%gp)) {
      if (defined($OUTFILE)) {
	$gp{$el}->write($OUTFILE);
      } else {
	$gp{$el}->print();
      }
    }
  }
}

# Return sorted array of references to element arrays.

sub contents {
  my $this = shift;
  my %hash = %$this;
  my @all;

  # Make an array of arrays of values for each element.
  my $row = 0;
  foreach my $gpref (sort hexadecimally keys(%hash)) {
    my %gp = %{$hash{$gpref}};
    foreach my $el (sort hexadecimally keys(%gp)) {
      my @values = $gp{$el}->values();
      $all[$row++] = \@values;
    }
  }

  @all = sort {sortByField()} @all;
  return @all;
}

# Set field index to sort by.  Return 1 if new index, else 0.

sub setIndex {
  my $this = shift;
  my ($val) = @_;

  # Don't sort by value.
  return 0 if ($val > 5);
  # Sorting by group or element equivalent to sorting by offset.
  $val = 2 if ($val <= 2);
  return 0 if (defined($sortIndex) and ($sortIndex == $val));
  $sortIndex = $val;
  return 1;
}

# Return sort index.

sub getIndex {
  return $sortIndex;
}

# Return value of the element at (group, element).

sub value {
  my $this = shift;
  my ($gp, $el) = @_;
  my $elem = $this->{uc($gp)}{uc($el)};
  return "" unless defined($elem);
  return (defined($elem->value())) ? $elem->value() : "";
}

# Return field of given index from element.
# Params: Group, Element, Field index.

sub field {
  my $this = shift;
  my ($gp, $el, $fieldname) = @_;
  my $elem = $this->{uc($gp)}{uc($el)};
  return "" unless defined($elem);
  return $elem->{$fieldname};
}

# Edit header value from string.
# String format: 'gggg,eeee=newvalue' or 'fieldname=newvalue'.
#   gggg, eeee = group, element (in hex); XXXX = new value.
#   fieldname = name of field from @dicom_fields.

sub editHeader {
  my ($this, $editstr) = @_;
  my ($gp, $el, $val);

  my $pos = index($editstr, '=');
  my $gpel = substr($editstr, 0, $pos);
  $val = substr($editstr, $pos + 1);
  if ($gpel =~ /^[0-9A-F]+,[0-9A-F]+/) {
    # Field specified as group and element.
    ($gp, $el) = split(/[^0-9A-F]+/, $gpel);
  } else {
    ($gp, $el) = $this->fieldByName($gpel);
  }
  return unless (defined($gp) and defined($el));
  $this->setElementValue($gp, $el, $val);
}

# Return group and element number of field with given name.

sub fieldByName {
  my ($this, $searchname) = @_;
  my ($gp, $el);

  # Field specified as field name: Search for it.
  my @allfields = $this->contents();
 FORE:
  foreach my $field (@allfields) {
    my @arr = @$field;
    if ($arr[5] eq $searchname) {
      ($gp, $el) = @arr[0, 1];
      last FORE;
    }
  }
  return ($gp, $el);
}

# Replace value of given element.

sub setElementValue {
  my $this = shift;
  my ($gp, $el, $newvalue) = @_;
  my $elem = $this->{$gp}{$el};
  $elem->setValue($newvalue);
}

#  ------------------------------------------------------------
#  Utility Functions (non-public)
#  ------------------------------------------------------------

sub hexadecimally {
  hex($a) <=> hex($b);
}

sub sortByField {
  my @aarr = @$a;
  my @barr = @$b;
  
  if ($aarr[$sortIndex] =~ /\D/) {
    return($aarr[$sortIndex] cmp $barr[$sortIndex]);
  } else {
    return($aarr[$sortIndex] <=> $barr[$sortIndex]);
  }
}

# Doesn't do anything in non-graphical case.
sub loop {}

1;
__END__

=head1 NAME

DICOM.pm is a Perl library that allows Perl programs to read the
headers of medical image files conforming to DICOM standards.

=head1 SYNOPSIS

  use DICOM;
  my $dicom = DICOM->new();
  $dicom->fill($dicomFile);
  my $patientName = $dicom->value('0010', '0010');
  
=head1 DESCRIPTION

DICOM (Digital Imaging and Communications in Medicine) is a standard
designed to allow medical image files to be transferred, stored and
viewed on different makes of computers. Perl is a multiplatform
language that excels at system tasks such as file manipulation. It's
easy to learn, particularly if you are familiar with C or the Unix
shells and utility programs.

This library provides the methods to read and parse a DICOM file, then
to recover the contents of each header element by their standard DICOM
group and element codes. Header element values can be edited (either
through the GUI or command line) and the modified file written back to
disk.

=head2 Methods

=over 4

=item * $object->fill($filename)

Fills the DICOM object with data from the file $filename

=back

=head1 SEE ALSO

The DICOM standard - http://medical.nema.org/

=head1 AUTHOR

Andrew Crabb, E<lt>ahc@jhu.eduE<gt>
Jonathan Harlap, E<lt>jharlap@bic.mni.mcgill.caE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2002 by Andrew Crabb
Some parts are Copyright (C) 2003 by Jonathan Harlap

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6.0 or,
at your option, any later version of Perl 5 you may have available.

=cut

# Element.pm ver 0.3
# Andrew Crabb (ahc@jhu.edu), May 2002.
# Element routines for DICOM.pm: a Perl module to read DICOM headers.
# $Id: Element.pm 4 2007-12-11 20:21:51Z jharlap $

# Each element is a hash with the following keys:
#   group	Group (hex).
#   element	Element within group (hex).
#   offset	Offset from file start (dec).
#   code	Field code eg 'US', 'UI'.
#   length	Field value length (dec).
#   name	Field descriptive name.
#   value	Value.
#   header	All bytes up to value, for easy writing.

package DICOM::Element;

use strict;
use DICOM::VRfields;
use vars qw($VERSION %VR);

$VERSION = sprintf "%d", q$Revision: 4 $ =~ /: (\d+)/;

#my %VR;			# Value Representations (DICOM Std PS 3.5 Sect 6.2)
my ($SHORT, $INT) = (2, 4);	# Constants: Byte sizes.
my ($FLOAT, $DOUBLE) = ('f', 'd');  # Constants: unpack formats
# Names of the element fields.
my @fieldnames = qw(group element offset code length name value header);
my $big_endian_machine = unpack("h*", pack("s", 1)) =~ /01/;

# Initialize VR hash only once.
# Fill in VR definitions from DICOM_fields.
BEGIN {
  foreach my $line (@VR) {
    next if ($line =~ /^\#/);
    my ($vr, $name, $len, $fix, $numeric, $byteswap) = split(/\t+/, $line);
    $VR{$vr} = [($name, $len, $fix, $numeric, $byteswap)];
  }
}

sub new {
  my $type = shift;
  my $self = {};
  return bless $self, $type;
}

# Fill in self from file.

sub fill {
  my $this = shift;
  my ($IN, $dictref, $big_endian_image) = @_;
  my %dict = %$dictref;
  #my ($group, $element, $offset, $code, $length, $name, $value, $header);
  my $vrstr;

  # Tag holds group and element numbers in two bytes each.
  $this->{'offset'} = tell($IN);
  $this->{'group'}    = sprintf "%04X", readInt($IN, $SHORT);
  $this->{'element'}  = sprintf "%04X", readInt($IN, $SHORT);

  if($this->{'group'} eq 'FFFFFFFF' && $this->{'element'} eq 'FFFFFFFF') { return 0; }

  # Next 4 bytes are either explicit VR or length (implicit VR).
  ($vrstr, $this->{'length'}) = readLength($IN);
  if(int($vrstr) == -1) { return 0; }

  # Go to record start, read bytes up to value field, store in header.
  my $diff = tell($IN) - $this->{'offset'};
  seek($IN, $this->{'offset'}, 0);
  read($IN, $this->{'header'}, $diff);

  if (exists($dict{$this->{'group'}}{$this->{'element'}})) {
      ($this->{'code'},$this->{'name'}) = @{$dict{$this->{'group'}}{$this->{'element'}}};
  } else {
      ($this->{'code'}, $this->{'name'}) = ("--", "UNKNOWN");
      $this->{'code'} = $vrstr if defined $vrstr;
  }

  # Read in the value field.  Certain fields need to be decoded.
  $this->{'value'} = "";
  if ($this->{'length'} > 0) {
#      print "Reading $this->{'group'}:$this->{'element'} ($this->{'code'} | $this->{'name'}) length $this->{'length'}\n";
    SWITCH: {
      # Decode ints and shorts.
      if ($this->{'code'} eq "UL") {$this->{'value'} = readInt($IN, $INT, $this->{'length'});  last SWITCH;}
      if ($this->{'code'} eq "US") {$this->{'value'} = readInt($IN, $SHORT, $this->{'length'});last SWITCH;}
      # Certain VRs not yet implemented: Single and double precision floats.
      if ($this->{'code'} eq "FL") {$this->{'value'} = readFloat($IN, $FLOAT, $this->{'length'}); last SWITCH;}
      if ($this->{'code'} eq "FD") {$this->{'value'} = readFloat($IN, $DOUBLE, $this->{'length'}); last SWITCH;}
      if ($this->{'code'} eq "SQ") {$this->{'value'} = readSequence($IN, $this->{'length'}); last SWITCH; }
      # Made it to here: Read bytes verbatim.
      read($IN, $this->{'value'}, $this->{'length'}) or die "read($this->{'group'}, $this->{'element'}, $this->{'length'})";
    }

    # byte swap value if appropriate
#    if($vrbyteswap && ($big_endian_image xor $big_endian_machine)) {
#	byteswap(\$this->{'value'});
#    }

    # UI may be padded with single trailing NULL (PS 3.5: 6.2.1)
    ($this->{'code'} eq "UI") and $this->{'value'} =~ s/\0$//;
  }

  return $this;
}

# readInt(instream, bytelength, fieldlength).
#   instream:	Input file stream.
#   bytelength: SHORT (2) or INT (4) bytes.
#   fieldlength:Total number of bytes in the field.
# If fieldlength > bytelength, multiple values are read in and
# stored as a string representation of an array.

sub readInt {
  my ($IN, $bytes, $len) = @_;
  my ($buff, $val, @vals);
  # Perl little endian decode format for short (v) or int (V).
  my $format = ($bytes == $SHORT) ? "v" : "V";
  $len = $bytes unless (defined($len));

  read($IN, $buff, $len) or return -1;
  if ($len == $bytes) {
    $val = unpack($format, $buff)+0;
  } else {
    # Multiple values: Create array.
    for (my $pos = 0; $pos < $len; $pos += 2) {
      push(@vals, unpack("$format", substr($buff, $pos, 2))+0);
    }
    $val = "[" . join(", ", @vals) . "]";
  }

  return $val;
}

sub writeInt {
  my ($this, $OUT, $bytes) = @_;
  my $val = $this->{value};
  my $format = ($bytes == $SHORT) ? "v" : "V";

  # Arrays of values stored as string [val1, val2, val3].
  $val =~ s/[\[\]]//g;
  my @vals = split(/\D+/, $val);
  foreach my $elem (@vals) {
    my $buff = pack("$format", $elem);
    print $OUT $buff;
  }
}

sub readFloat {
    my ($IN, $format, $len) = @_;
    my ($buff, $val);

    read($IN, $buff, $len);

    $val = unpack($format, $buff);
    return sprintf("%e", $val);
}

sub readSequence {
    my ($IN, $len) = @_;
    my ($buff, $val);

#    print "0xFFFE has length: ".length(0xFFFE)." and looks like ".sprintf("%x", 0xFFFE)."\n";
#
#    printf "READING SQ AT ".tell($IN)." LENGTH: %x\n", $len;
#    if($len == 0xFFFFFFFF) { print "length is FFFF, FFFF\n"; }
#    else {print "length is NOT F's\n"; }

    # three different cases:
    # implicit VR, explicit length
    # explicit VR, undefined length, items of defined length (w/end delimiter)
    # implicit VR, undefined length, items of undefined length

    # defined length
    if($len > 0 and $len != 0xFFFFFFFF) {
#	printf "skipping forward 0x%x bytes\n", $len;
	read($IN, $buff, $len);
    } else {
      READLOOP:
	while(read($IN, $buff, 2)) {
	    $buff = unpack('v', $buff);
	    if($buff == 0xFFFE) {
#		print "found start of delimiter\n";
		read($IN, $buff, 2);
		$buff = unpack('v', $buff);
		if($buff == 0xE0DD) {
#		    print "found end of delimiter\n";
		    read($IN, $buff, 4);
		    $buff = unpack('v', $buff);
		    if($buff == 0x00000000) {
#			print "found length 0\n";
			last READLOOP;
		    } else {
			seek($IN, -4, 1);
		    }
		} else {
		    seek($IN, -2, 1);
		}
	    }
	}
    }

    return 'skipped';
}


# Return the Value Field length, and length before Value Field.
# Implicit VR: Length is 4 byte int.
# Explicit VR: 2 bytes hold VR, then 2 byte length.

sub readLength {
  my ($IN) = @_;
  my ($b0, $b1, $b2, $b3);
  my ($buff, $vrstr);

  # Read 4 bytes into b0, b1, b2, b3.
  foreach my $var (\$b0, \$b1, \$b2, \$b3) {
      my $success = read($IN, $$var, 1);
      if(!$success) { print "readLength died - this is likely not a good DICOM file\n"; return -1; }
    $$var = unpack("C", $$var);
  }
  # Temp string to test for explicit VR
  $vrstr = pack("C", $b0) . pack("C", $b1);
#print "Pos: ".tell($IN)." VR: $vrstr B0: $b0 B1: $b1 B2: $b2 B3: $b3\n";
  # Assume that this is explicit VR if b0 and b1 match a known VR code.
  # Possibility (prob 26/16384) exists that the two low order field length 
  # bytes of an implicit VR field will match a VR code.

  # DICOM PS 3.5 Sect 7.1.2: Data Element Structure with Explicit VR
  # Explicit VRs store VR as text chars in 2 bytes.
  # VRs of OB, OW, SQ, UN, UT have VR chars, then 0x0000, then 32 bit VL:
  #
  # +-----------------------------------------------------------+
  # |  0 |  1 |  2 |  3 |  4 |  5 |  6 |  7 |  8 |  9 | 10 | 11 |
  # +----+----+----+----+----+----+----+----+----+----+----+----+
  # |<Group-->|<Element>|<VR----->|<0x0000->|<Length----------->|<Value->
  #
  # Other Explicit VRs have VR chars, then 16 bit VL:
  #
  # +---------------------------------------+
  # |  0 |  1 |  2 |  3 |  4 |  5 |  6 |  7 |
  # +----+----+----+----+----+----+----+----+
  # |<Group-->|<Element>|<VR----->|<Length->|<Value->
  #
  # Implicit VRs have no VR field, then 32 bit VL:
  #
  # +---------------------------------------+
  # |  0 |  1 |  2 |  3 |  4 |  5 |  6 |  7 |
  # +----+----+----+----+----+----+----+----+
  # |<Group-->|<Element>|<Length----------->|<Value->

  my $length = undef;
  if(defined($VR{$vrstr})) {
      # Have a code for an explicit VR: Retrieve VR element
      my $ref = $VR{$vrstr};
      my ($name, $bytes, $fixed, $numeric, $byteswap) = @$ref;
      if ($bytes == 0) {
	# This is an OB, OW, SQ, UN or UT: 32 bit VL field.
	# Have seen in some files length 0xffff here...
	$length = readInt($IN, $INT);
      } else {
	# This is an explicit VR with 16 bit length.
	$length = ($b3 << 8) + $b2;
    }
  } else {
      # Made it to here: Implicit VR, 32 bit length.
      $length = ($b3 << 24) + ($b2 << 16) + ($b1 << 8) + $b0 unless defined $length;
      $vrstr = undef;
  }

  # Return the value
  return ($vrstr, $length);
}

# Return the values of each field.

sub values {
  my $this = shift;
  my %hash = %$this;

  # Fieldnames are group element offset code length name value header.
  my @vals = @hash{@fieldnames};
  @vals = splice(@vals, 0, 6);	# Omit value & header.
  push(@vals, $this->valueString());		# Add value.
  return @vals;
}

# Print formatted representation of element to stdout.

sub print {
  my $this = shift;
  my ($gp, $el, $off, $code, $len, $name, $val) = $this->values();

  printf "(%04X, %04X) %s %6d: %-33s = %s\n", hex($gp), hex($el), $code, $len, $name, $val;
}

# Return a string representation of the value field (null if binary).

sub valueString {
  my $this = shift;
  my %hash = %$this;
  my ($code, $value) = @hash{qw(code value)};

  if ($code =~ /OX|SQ/) {
      $value = "";
  } elsif ($code eq '--') {
      # Don't return value if it contains binary characters.
      if(defined($this->{'length'})) {
	  foreach my $i (0..($this->{'length'} - 1)) {
	      my $val = ord(substr($value, $i, 1));
	      $value = "" if ($val > 0x0 and ($val < 0x20 or $val >= 0x80));
	  }
      } else {
	  $value = "";
      }
  } 
  
  return $value;
}

# Write this data element to disk.  All fields up to value are stored in 
# immutable field 'header' - write this to disk then value field.

sub write {
  my ($this, $OUTFILE) = @_;
  my %hash = %$this;
  my ($gp, $el, $offs, $code, $len, $name, $valstr) = $this->values();
  my ($hdr, $val) = @hash{qw(header value)};

  print $OUTFILE $hdr;
 SWITCH: {
  if ($code eq "UL") { $this->writeInt($OUTFILE, $INT);   last SWITCH; }
  if ($code eq "US") { $this->writeInt($OUTFILE, $SHORT); last SWITCH; }
  
  # Trim value to length (may have been edited), null pad if necessary.
#    $val = substr($val, 0, $len);
  foreach my $i (1..($len - length($val))) {
    $val = "$val\0";
  }
  print $OUTFILE $val;
  }
}

sub value {
  my $this = shift;

  return $this->{'value'};
}

# Set the value field of this element.  Truncates to max length.

sub setValue {
  my $this = shift;
  my ($value) = @_;
  $value = substr($value, 0, $this->{'length'});

  $this->{'value'} = $value;
}

sub byteswap {
    my ($valref) = @_;
    
    my $packed = 0;
    if(length($$valref) % 2 != 0) {
	$packed = 1;
	substr($$valref, -1, 1) = "x".substr($$valref, -1, 1);
    }
    $$valref = pack('n*', unpack('v*', $$valref));
    if($packed) {
	substr($$valref, -1, 1) = '';
    }
}
1;
__END__


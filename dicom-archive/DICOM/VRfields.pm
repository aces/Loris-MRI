package DICOM::VRfields;

=pod

=head1 NAME

DICOM::VRfields -- Value Representations (DICOM Standard PS 3.5 Sect 6.2)

=head1 SYNOPSIS

  use DICOM::Element;
  use DICOM::Fields;	# Standard header definitions.
  use DICOM::Private;	# Private or custom definitions.

  # Initialize VR hash.
  # Fill in VR definitions from DICOM_fields.
  BEGIN {
    foreach my $line (@VR) {
      next if ($line =~ /^\#/);
      my ($vr, $name, $len, $fix, $numeric, $byteswap) = split(/\t+/, $line);
      $VR{$vr} = [($name, $len, $fix, $numeric, $byteswap)];
    }
  }

=head1 DESCRIPTION

Value Representations (DICOM Standard PS 3.5 Sect 6.2)
  - Bytes=0 => Undefined length.
  - Fixed=1 => Exact field length, otherwise max length.

Simply creating an array of DICOM Value Representations:

  Code  Name                     Bytes  Fixed  Numeric  ByteSwap
  AE    'Application Entity'     16     0      0        0
  AS    'Age String'             4      1      0        0
  AT	'Attribute Tag'          4      1      0        1
  CS    'Code String'            16     0      0        0
  DA    'Date'                   8      1      0        0
  DS    'Decimal String'         16     0      1        0
  DT    'Date Time'              26     0      0        0
  FL    'Floating Point Single'  4      1      1        1
  FD    'Floating Point Double'  8      1      1        1
  IS    'Integer String'         12     0      1        0
  LO    'Long Strong'            64     0      0        0
  LT    'Long Text'              10240  0      0        0
  OB    'Other Byte String'  	 0      0      0        0
  OW    'Other Word String' 	 0      0      0        1
  PN    'Person Name'	         64     0      0        0
  SH    'Short String'           16     0      0        0
  SL    'Signed Long'	         4      1      1        1
  SQ    'Sequence of Items'      0      0      0        0
  SS    'Signed Short'           2      1      1        1
  ST    'Short Text'             1024   0      0        0
  TM    'Time'                   16     0      0        0
  UI    'Unique Identifier UID'  64     0      0        0
  UL    'Unsigned Long'          4      1      1        1
  UN    'Unknown'                0      0      0        0
  US    'Unsigned Short'         2      1      1        1
  UT    'Unlimited Text'         0      0      0        0

=cut


use strict;
use vars qw(@ISA @EXPORT $VERSION @VR);

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(@VR);
$VERSION = sprintf "%d", q$Revision: 4 $ =~ /: (\d+)/;

# Value Representations (DICOM Standard PS 3.5 Sect 6.2)
# Bytes=0 => Undefined length.
# Fixed=1 => Exact field length, otherwise max length.
# Code  Name                    Bytes   Fixed   Numeric ByteSwap

@VR = (<<END_VR =~ m/^\s*(.+)/gm);
AE	'Application Entity'	16	0	0	0
AS	'Age String'		4	1	0	0
AT	'Attribute Tag'		4	1	0	1
CS	'Code String'		16	0	0	0
DA	'Date'			8	1	0	0
DS	'Decimal String'	16	0	1	0
DT	'Date Time'		26	0	0	0
FL	'Floating Point Single'	4	1	1	1
FD	'Floating Point Double'	8	1	1	1
IS	'Integer String'	12	0	1	0
LO	'Long Strong'		64	0	0	0
LT	'Long Text'		10240	0	0	0
OB	'Other Byte String'	0	0	0	0
OW	'Other Word String'	0	0	0	1
PN	'Person Name'		64	0	0	0
SH	'Short String'		16	0	0	0
SL	'Signed Long'		4	1	1	1
SQ	'Sequence of Items'	0	0	0	0
SS	'Signed Short'		2	1	1	1
ST	'Short Text'		1024	0	0	0
TM	'Time'			16	0	0	0
UI	'Unique Identifier UID'	64	0	0	0
UL	'Unsigned Long'		4	1	1	1
UN	'Unknown'		0	0	0	0
US	'Unsigned Short'	2	1	1	1
UT	'Unlimited Text'	0	0	0	0
END_VR


=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

Andrew Crabb (ahc@jhu.edu),
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut


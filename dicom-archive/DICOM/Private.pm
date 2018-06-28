package DICOM::Private;

=pod

=head1 NAME

DICOM::Private -- Definitions of (optional) private fields of DICOM headers.

=head1 SYNOPSIS

  use DICOM::Element;
  use DICOM::Fields;	# Standard header definitions.
  use DICOM::Private;	# Private or custom definitions.

  # Initialize dictionary.
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

=head1 DESCRIPTION

Definitions of (optional) private fields of DICOM headers. By default, none
are defined in the LORIS-MRI code base but users could define them here.

Example format:

  0000   0000   UL   1      GroupLength
  ...

=cut


use strict;
use vars qw(@ISA @EXPORT $VERSION @dicom_private);

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(@dicom_private);
$VERSION = sprintf "%d", q$Revision: 4 $ =~ /: (\d+)/;

# These definitions override those with the same group and element
# numbers in dicom_fields.

@dicom_private = (<<END_DICOM_PRIVATE =~ m/^\s*(.+)/gm);
# Example format:
# 0000   0000   UL   1      GroupLength
END_DICOM_PRIVATE


=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut
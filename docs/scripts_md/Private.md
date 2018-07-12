# NAME

DICOM::Private -- Definitions of (optional) private fields of DICOM headers.

# SYNOPSIS

    use DICOM::Element;
    use DICOM::Fields;    # Standard header definitions.
    use DICOM::Private;   # Private or custom definitions.

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

# DESCRIPTION

Definitions of (optional) private fields of DICOM headers. By default, none
are defined in the LORIS-MRI code base but users could define them here.

Example format:

    0000   0000   UL   1      GroupLength
    ...

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

# NAME

DICOM::Fields -- Definitions of fields of DICOM headers.

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

Definitions of fields of DICOM headers. This file is provided purely for
experimental use.

Simply creating an array of:

    0000   0000   UL   1      GroupLength
    0000   0001   UL   1      CommandLengthToEnd
    0000   0002   UI   1      AffectedSOPClassUID
    0000   0003   UI   1      RequestedSOPClassUID
    0000   0010   CS   1      CommandRecognitionCode
    0000   0100   US   1      CommandField
    0000   0110   US   1      MessageID
    0000   0120   US   1      MessageIDBeingRespondedTo
    0000   0200   AE   1      Initiator
    0000   0300   AE   1      Receiver
    0000   0400   AE   1      FindLocation
    0000   0600   AE   1      MoveDestination
    0000   0700   US   1      Priority
    0000   0800   US   1      DataSetType
    0000   0850   US   1      NumberOfMatches
    0000   0860   US   1      ResponseSequenceNumber
    0000   0900   US   1      Status
    0000   0901   AT   1-n    OffendingElement
    0000   0902   LO   1      ErrorComment
    0000   0903   US   1      ErrorID
    ...

# LICENSING

License: GPLv3

# AUTHORS

Andrew Crabb (ahc@jhu.edu),
LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

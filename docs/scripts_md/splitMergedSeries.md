# NAME

splitMergedSeries.pl -- a script that goes through the supplied directory
with DICOM files (or the supplied DICOM archive) and generates a specfile which
can be used to fix the DICOM fields of difficult to separate series.

# SYNOPSIS

perl tools/splitMergedSeries.pl `[options]` `[/path/to/DICOM/or/TARCHIVE]` `[specfile_name]`

Available options are:

\-series : Split series by generating new series numbers \[default\]

\-seqnam : Split series by modifying the sequence name

\-echo   : Split series by generating new echo numbers

\-clobber: Overwrite the existing `specfile`

\-verbose: Be verbose

\-debug  : Be even more verbose

# DESCRIPTION

This script goes through the supplied directory with DICOM files (or supplied
DICOM archive) and generates a `specfile` which can be used to fix the DICOM
fields of difficult to separate series. Specifically, the specfile will:

1\. Insert `EchoNumber` values in case this field was not set for a
   multi-echo sequence
2\. Insert or modify a field if multiple repeats of the same sequence are
   present (and not otherwise separated). The user can select which field
   is modified by selecting one of the sequence splitting options.

The resulting `specfile` can be used as input to `updateHeadersBatch.pl`.

# TODO

Make fully sure this works as expected.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

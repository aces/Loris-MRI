# NAME

get\_dicom.pl - extracts DICOM files for specific patient names/scan types

# SYNOPSIS

perl get\_dicom.pl \[-p profile\] \[-n patient\_name\_patterns\] \[-t scan\_type\_patterns\] \[-d tmp\_dir\] \[-o tarBasename\]

Available options are:

\-p      : name of the config file in `../dicom-archive/.loris_mri` (defaults to
          prod).
\-n      : comma separated list of MySQL patterns for the patient names that a DICOM file
          has to have in order to be extracted. A DICOM file only has to match one of the 
          patterns to be extracted. If no pattern is specified, then the patient name is 
          not used to determine which DICOM files to extract.
\-t      : comma separated list of MySQL patterns of the acquisition protocols (scan types
          names) that a DICOM file has to have in order to be extracted. A DICOM file only
          has to match one of the patterns to be extracted. If no pattern is specified, then
          the scan type name is not used to determine which DICOM files to extract.
\-d      : extract the files in directory &lt;dir\_argument>/get\_dicom.pl.<UNIX\_process\_number>
          For example with -d /data/tmp, the DICOM files will be extracted in 
          /data/tmp/get\_dicom.pl.67888 (assuming 67888 is the process number). By default, dir\_argument
          is set to /tmp.
\-o      : basename of the final tar.gz file to produce, in the current directory (defaults to dicoms.tar.gz)

# DESCRIPTION

This script first connects to the database to build the list of tarchives for which
the patient names match the list of patterns specified as argument. The script will then examine 
these tarchives and look for the MINC files whose scan types (acquisition protocol names) match 
the list of patterns passed as argument. It then extracts the DICOM files associated to each
MINC file and writes them in the extraction directory (see -d option), in a subdirectory with name

&lt;pscid>/&lt;visit\_label>/&lt;acquisition\_date>/&lt;protocol>\_&lt;minc\_index>

where &lt;minc\_index> is the index number of the MINC file to which the DICOMs are associated.
Finally, a tar is created which contains all the DICOM files that were extract

## Methods

### rmTmpExtractDir()

Function that deletes directory $tmpExtractDir and all its contents if 
variable $tmpExtractDir is defined. 

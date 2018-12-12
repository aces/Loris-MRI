# NAME

get\_dicom\_files.pl - extracts DICOM files for specific patient names/scan types

# SYNOPSIS

perl get\_dicom\_files.pl \[-n patient\_name\_patterns\] \[-t scan\_type\_patterns\] \[-d tmp\_dir\] \[-o tarBasename\] -profile profile

Available options are:

\-profile : name of the config file in `../dicom-archive/.loris_mri` (typically `prod`)

\-n       : comma separated list of MySQL patterns for the patient names that a DICOM file
           has to have in order to be extracted. A DICOM file only has to match one of the 
           patterns to be extracted. If no pattern is specified, then the patient name is 
           not used to determine which DICOM files to extract. This option must be used if
           no scan type patterns were specified with `-t` (see below).

\-t       : comma separated list of MySQL patterns of the acquisition protocols (scan types
           names) that a DICOM file has to have in order to be extracted. A DICOM file only
           has to match one of the patterns to be extracted. If no pattern is specified, then
           the scan type name is not used to determine which DICOM files to extract. This option
           must be used if no patient name patterns were specified via `-n` (see above).

\-d       : extract the files in directory `<dir_argument>/get_dicom_files.pl.<UNIX_process_number>`
           For example with `-d /data/tmp`, the DICOM files will be extracted in 
           `/data/tmp/get_dicom_files.pl.67888` (assuming 67888 is the process number). 
           By default, dir\_argument is set to the value of the environment variable `TMPDIR`.

\-o       : basename of the final `tar.gz` file to produce, in the current directory (defaults to 
           `dicoms.tar.gz`).

# DESCRIPTION

This script first connects to the database to build the list of DICOM archives for which
the patient names match the list of patterns specified as argument, or all DICOM archives if
no patterns were specified. The script will then examine these DICOM archives and look for the 
MINC files whose scan types (acquisition protocol names) match the list of patterns passed as 
argument, or all MINC files for that archive if `-t` was not used. It then extracts the DICOM files
associated to each MINC file and writes them in the extraction directory (see `-d` option), in a 
subdirectory with name

`<pscid>/<visit_label>/<acquisition_date>/<protocol>_<minc_index>`

where `<minc_index>` is the index number of the MINC file to which the DICOMs are associated: 
e.g. for file `loris_300001_V4_DtiSA_002.mnc`, the MINC index is 2 (i.e. the second MINC file with 
scan type `DtiSA`). Finally, a `.tar.gz` that contains all the DICOM files that were extracted is 
created.

## Methods

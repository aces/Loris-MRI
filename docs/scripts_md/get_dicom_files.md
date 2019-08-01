# NAME

get\_dicom\_files.pl - extracts DICOM files for specific patient names/scan types

# SYNOPSIS

perl get\_dicom\_files.pl \[-names patient\_name\_patterns\] \[-types scan\_type\_patterns\] \[-outdir tmp\_dir\] \[-outfile tarBasename\] 
           \[-id candid|pscid|candid\_pscid|pscid\_candid\] -profile profile

Available options are:

\-profile : name of the config file in `../dicom-archive/.loris_mri` (typically `prod`)

\-names   : comma separated list of MySQL patterns for the patient names that a DICOM file
           has to have in order to be extracted. A DICOM file only has to match one of the 
           patterns to be extracted. If no pattern is specified, then the patient name is 
           not used to determine which DICOM files to extract. This option must be used if
           no scan type patterns were specified with `-type` (see below).

\-types   : comma separated list of MySQL patterns of the acquisition protocols (scan types
           names) that a DICOM file has to have in order to be extracted. A DICOM file only
           has to match one of the patterns to be extracted. If no pattern is specified, then
           the scan type name is not used to determine which DICOM files to extract. This option
           must be used if no patient name patterns were specified via `-names` (see above).

\-outdir  : extract the files in directory `<dir_argument>/get_dicom_files.pl.<random_string>`
           For example with `-d /data/tmp`, the DICOM files might be extracted in 
           `/data/tmp/get_dicom_files.pl.n1d4`. By default, dir\_argument is set to the value of
           the environment variable `TMPDIR`. Since the UNIX program `tar` has known limitations 
           with NFS file systems (incorrect reports of files that changed while they are archived), the
           argument to `-d` should not be a directory that resides on an NFS mounted file system.
           Failure to do so might result in `get_dicom_files.pl` failing.

\-outfile : basename of the final `tar.gz` file to produce, in the current directory (defaults to 
           `dicoms.tar.gz`).

\-id      : how to name the subdirectory identifying the candidate to which the DICOM files belong:
           pscid, candid, pscid\_candid or candid\_pscid (defaults to candid)

# DESCRIPTION

This script first connects to the database to build the list of DICOM archives for which
the patient names match the list of patterns specified as argument, or all DICOM archives if
no patterns were specified. The script will then examine these DICOM archives and look for the 
MINC files whose scan types (acquisition protocol names) match the list of patterns passed as 
argument, or all MINC files for that archive if `-types` was not used. It then extracts the DICOM files
associated to each MINC file and writes them in the extraction directory (see `-outdir` option), in a 
subdirectory with name

`<dccid>/<visit_label>/<acquisition_date>/<protocol>_<minc_index>_<series_description`

where `<minc_index>` is the index number of the MINC file to which the DICOMs are associated: 
e.g. for file `loris_300001_V4_DtiSA_002.mnc`, the MINC index is 2 (i.e. the second MINC file with 
scan type `DtiSA`). Note that the `dccid` subdirectory in the file path can be changed to another
identifier with option `-id`. Finally, a `.tar.gz` that contains all the DICOM files that were extracted
is created.

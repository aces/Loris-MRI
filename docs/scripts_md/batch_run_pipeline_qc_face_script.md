# NAME

batch\_run\_pipeline\_qc\_face\_script.pl -- Run `pipeline_qc_deface.pl` in batch mode

# SYNOPSIS

perl batch\_run\_pipeline\_qc\_face\_script.pl \[-profile file\] \[-out\_basedir directory\] < list\_of\_files.txt

Available options are:

\-profile: name of config file in ../dicom-archive/.loris\_mri (typically called prod)

\-out\_basedir: path to the output base directory where the jpg will be created

# DESCRIPTION

This script creates the 3D rendering QC images on multiple MINC files.
The list of MINC files to use to generate those 3D JPEG images are provided
through a text file (e.g. `list_of_files.txt` with one file path per line).

An example of what a `list_of_files.txt` might contain for 3 files to use to
create a 3D JPEG rendering of a scan to be defaced:
 /data/project/data/assembly/123456/V01/mri/processed/MINC\_deface/project\_123456\_V01\_t1w\_001\_t1w-defaced\_001.mnc
 /data/project/data/assembly/123456/V01/mri/processed/MINC\_deface/project\_123456\_V01\_t1w\_002\_t1w-defaced\_001.mnc
 /data/project/data/assembly/123456/V01/mri/processed/MINC\_deface/project\_123456\_V01\_t2w\_001\_t2w-defaced\_001.mnc

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

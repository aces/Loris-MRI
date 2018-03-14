# NAME

batch\_uploads\_imageuploader -- a script that runs imaging\_upload\_file.pl in
batch mode

# SYNOPSIS

./batch\_uploads\_imageuploader -profile prod < list\_of\_scans.txt > log\_batch\_imageuploader.txt 2>&1 \`\[options\]\`

Available options are:

\-profile      : name of the config file in
                `../dicom-archive/.loris_mri`

\-verbose      : if set, be verbose

# DESCRIPTION

This script runs the Loris-MRI insertion pipeline on multiple scans. The list of
scans are provided through a text file (e.g. `list_of_scans.txt`) with one scan
details per line.
The scan details includes the path to the scan, identification as to whether the
scan is for a phantom (Y) or not (N), and the candidate name for non-phantom
entries.

Like the LORIS Imaging Uploader interface, this script also validates the
candidate's name against the (start of the) filename and creates an entry in the
`mri_upload` table.

An example of what `list_of_scans.txt` might contain for 3 uploads to be
inserted:

    /data/incoming/PSC0001_123457_V1.tar.gz N PSC0000_123456_V1
    /data/incoming/lego_Phantom_MNI_20140101.zip Y
    /data/incoming/PSC0001_123457_V1_RES.tar.gz N PSC0000_123456_V1

## Methods

### insertIntoMRIUpload($patientname, $phantom, $fullpath)

Function that inserts into the `mri_upload` table entries for data coming from
the list of scans in the text file provided when calling
batch\_upload\_imageuploader

INPUTS  :
    - $patientname  : The patient name
    - $phantom      : 'Y' if the entry is for a phantom,
                      'N' otherwise
    - $fullpath     : Path to the uploaded file

RETURNS: $upload\_id : The upload ID

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

# NAME

BackPopulateSNRAndAcquisitionOrder.pl -- a script that back populates the
`AcqOrderPerModality` column of the `files` table, and the signal-to-noise
ratio (SNR) values in the `parameter_file` table for inserted MINC files. The
SNR is computed using MINC tools built-in algorithms.

# SYNOPSIS

perl tools/BackPopulateSNRAndAcquisitionOrder.pl `[options]`

Available options are:

\-profile    : name of the config file in `../dicom-archive/.loris_mri`

\-tarchive\_id: ID of the DICOM archive (.tar file) to be processed from the
               `tarchive` table

# DESCRIPTION

This script will back populate the `files` table with entries for the
`AcqOrderPerModality` column; in reference to:
https://github.com/aces/Loris-MRI/pull/160
as well as populate the `parameter_file` table with SNR entries in reference
to: https://github.com/aces/Loris-MRI/pull/142
It can take in `TarchiveID` as an argument if only a specific DICOM archive
(.tar files) is to be processed; otherwise, all DICOM archives (`tar`
files) in the `tarchive` table are processed.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

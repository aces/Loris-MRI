# NAME

BackPopulateSNRAndAcquisitionOrder.pl -- a script that back populates the
AcqOrderPerModality column of the files table, and the signal-to-noise (SNR)
values in the parameter\_file table for inserted MINC files. The SNR is computed
using algorithms built-in the MINC tools.

# SYNOPSIS

perl tools/BackPopulateSNRAndAcquisitionOrder.pl \`\[options\]\`

Available options are:

\-profile        : name of the config file in
                  `../dicom-archive/.loris_mri`

\-tarchive\_id    : The tarchive ID of the .tar to be processed from the tarchive
                  table

# DESCRIPTION

This script will back populate the files table with entries for the
AcqOrderPerModality column; in reference to:
https://github.com/aces/Loris-MRI/pull/160
as well as populate the parameter\_file table with SNR entries in reference to:
https://github.com/aces/Loris-MRI/pull/142
It can take in tarchiveID as an argument if only a specific .tar is to be
processed; otherwise, all .tar in the tarchive table are processed.

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

# NAME

remove\_jiv\_data\_from\_db\_and\_filesystem.pl -- Cleans up the JIV data from the
database tables and the filesystem

# SYNOPSIS

perl remove\_jiv\_data\_from\_db\_and\_filesystem.pl `[options]`

Available option is:

\-profile: name of the config file in ../dicom-archive/.loris\_mri

# DESCRIPTION

This script will remove the JIV files from the `parameter_file` table and
move them to the `$data_dir/archive/bkp_jiv_produced_before_LORIS_20.0` directory of the filesystem for
projects that wish to clean up the JIV data produced in the past. Note that
from release 20.0, JIV datasets will not be produced anymore by the imaging
insertion scripts.

## Methods

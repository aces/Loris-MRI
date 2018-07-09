# NAME

remove\_jiv\_data\_from\_db\_and\_filesystem.pl -- Cleans up the JIV data from the
database tables and the filesystem

# SYNOPSIS

perl remove\_jiv\_data\_from\_db\_and\_filesystem.pl `[options]`

Available option is:

\-profile: name of the config file in ../dicom-archive/.loris\_mri

# DESCRIPTION

This script will remove the JIV files from the parameter\_file table and the
filesystem for projects that wish to clean up and remove completely the JIV
data produced in the past. From now on, JIV datasets will not be produced
anymore.

## Methods

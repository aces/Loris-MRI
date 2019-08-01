# NAME

batch\_uploads\_tarchive - upload a batch of DICOM archives using script
`tarchiveLoader.pl`

# SYNOPSIS

./batch\_uploads\_tarchive

# DESCRIPTION

This script uploads a list of DICOM archives to the database by calling script
`tarchiveLoader.pl` on each file in succession. The list of files to process is read 
from `STDIN`, one file name per line. Each file name is assumed to be a path
relative to `tarchiveLibraryDir` (see below).

The following settings of file `$ENV{LORIS_CONFIG}/.loris-mri/prod` affect the 
behvaviour of `batch_uploads_tarchive` (where `$ENV{LORIS_CONFIG}` is the
value of the Unix environment variable `LORIS_CONFIG`):

- **dataDirBasepath** : controls where the `STDOUT` and `STDERR` of each qsub
command (see below) will go, namely in
  `$dataDirBasepath/batch_output/tarstdout.log<index>` and
  `$dataDirBasepath/batch_output/tarstderr.log<index>`
  (where `<index>` is the index of the DICOM archive processed, the
  first file having index 1).
- **tarchiveLibraryDir**: directory that contains the DICOM archives to process.
The path of the files listed on `STDIN` should be relative to this directory.
- **is\_qsub**: whether the output (STDOUT) of each `tarchiveLoader.pl` command
should be processed by the `qsub` Unix command (allows batch execution of jobs
on the Sun Grid Engine, if available). If set, then the `qsub` command will
send its `STDOUT` and `STDERR` according to the value of `dataDirBasepath`
(see above).
- **mail\_use**: upon completion of the script, an email will be sent to email address
  $mail\_user containing the list of files processed by `batch_uploads_tarchive`

File prod should also contain the information needed to connect to the database in an
array `@db` containing four elements:

- The database name
- The SQL user name used to connect ot the database
- The password for the user identified above
- The database hostname

# TO DO

Code cleanup: remove unused `-D` and `-v` program arguments

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

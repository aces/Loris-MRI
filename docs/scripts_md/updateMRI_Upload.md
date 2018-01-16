# NAME

updateMRI\_Upload.pl - updates database table mri\_upload according to an entry in table
   tarchive

# SYNOPSIS

updateMRI\_Upload.pl \[options\] -profile prod -tarchivePath tarchivePath -source\_location source\_location

- **-profile prof** : (mandatory) path (absolute or relative to the current directory) of the 
    profile file
- **-tarchivePath tarchivePath** : (mandatory) absolute path to the tarchive file
- **-source\_location source\_location** : (mandatory) value to set column 
    DecompressedLocation to for the newly created record in table mri\_upload (see below)
- **-globLocation** : Loosen the validity check of the tarchive allowing for the 
     possibility that the tarchive was moved to a different directory.
- **-verbose** : Be verbose

# DESCRIPTION

This script first starts by reading the `prod` file (argument passed to the `-profile` switch)
to fetch the `@db` variable, a Perl array containing four elements: the database
name, the databse user name used to connect to the database, the password and the 
database hostname. It then checks for an entry in table `tarchive` with the same 
`ArchiveLocation` as the tarchive file passed on the command line. Let `T` be the 
tarchive record found. The script will then proceed to scan table `mri_upload` for a 
record with the same `tarchiveID` as `T`'s. If there is none (which is the expected 
outcome), it will insert a record in `mri_upload` with the following properties/values:

- `UploadedBy` : Unix username of the person currently running `updateMRI_upload.pl`
- `uploadDate`: timestamp representing the moment at which `updateMRI_upload.pl` was run
- `tarchiveID`: value of `tarchiveID` for record `T` in table `tarchive`
- `DecompressedLocation`: argument of the `-source_location` switch passed on the command line

If there already is an entry in `mri_upload` with the same `ArchiveLocation` as `T`'s, the script
will exit with an error message saying that `mri_upload` is already up to date with respect to
`T`. 

# TO DO

Nothing.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS
Zia Mohades 2014 (zia.mohades@mcgill.ca)

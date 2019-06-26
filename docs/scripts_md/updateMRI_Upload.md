# NAME

updateMRI\_Upload.pl - updates database table `mri_upload` according to an entry in table
   `tarchive`.

# SYNOPSIS

updateMRI\_Upload.pl \[options\] -profile prod -tarchivePath tarchivePath -source\_location source\_location -timeZone tz

- **-profile prod** : (mandatory) path (absolute or relative to the current directory) of the 
    profile file
- **-tarchivePath tarchivePath** : (mandatory) absolute path to the DICOM archive
- **-source\_location source\_location** : (mandatory) value to set column 
    `DecompressedLocation` for the newly created record in table `mri_upload` (see below)
- **-globLocation** : loosen the validity check of the DICOM archive allowing for the 
     possibility that it was moved to a different directory.
- **-verbose** : be verbose

# DESCRIPTION

This script first starts by reading the `prod` file (argument passed to the `-profile` switch)
to fetch the `@db` variable, a Perl array containing four elements: the database
name, the database user name used to connect to the database, the password and the 
database hostname. It then checks for an entry in the `tarchive` table with the same 
`ArchiveLocation` as the DICOM archive passed on the command line. Let `T` be the 
DICOM archive record found in the `tarchive` table. The script will then proceed to scan table 
`mri_upload` for a record with the same `tarchiveID` as `T`'s. If there is none (which is the 
expected outcome), it will insert a record in `mri_upload` with the following properties/values:

- `UploadedBy` : Unix username of the person currently running `updateMRI_upload.pl`
- `uploadDate`: timestamp representing the moment at which `updateMRI_upload.pl` was run
- `tarchiveID`: value of `tarchiveID` for record `T` in table `tarchive`
- `DecompressedLocation`: argument of the `-source_location` switch passed on the command line

If there already is an entry in `mri_upload` with the same `ArchiveLocation` as `T`'s, the script
will exit with an error message saying that `mri_upload` is already up to date with respect to
`T`.

# LICENSING

License: GPLv3

# AUTHORS

Zia Mohades 2014 (zia.mohades@mcgill.ca),
LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

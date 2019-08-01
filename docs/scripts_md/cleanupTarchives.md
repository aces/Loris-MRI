# NAME

cleanupTarchives.pl -- script to clean up duplicated DICOM archives in the filesystem

# SYNOPSIS

perl cleanupTarchives.pl `[options]`

Available options are:

\-profile: name of the config file in `../dicom-archive/.loris-mri`

# DESCRIPTION

The program greps the list of `ArchiveLocation`/`md5sumArchive` from the
`tarchive` table of the database and compares it to the list of DICOM archive
files present in the filesystem. If more than one file is found on the
filesystem for a given database entry, it will compare the `md5sum` and the archive
location and remove the duplicate DICOM archives that do not match both the `md5sum`
and the archive location.

## Methods

### readTarDir($tarDir, $match)

Read the `tarchive` library folder and return the list of files matching the regex
stored in `$match`.

INPUTS:
  - $tarDir: `tarchive` library directory (in which DICOM archives are stored)
  - $match : regular expression to use when parsing the DICOM archive library folder

RETURNS: the list of matching DICOM archives into a dereferenced array

### getTarList($tarchiveLibraryDir, $match)

Read the year sub-folders in the DICOM archive library folder and return the list of
files matching the regex stored in `$match`.

INPUTS:
  - $tarDir     : `tarchive` library directory (in which DICOM archives are stored)
  - $YearDirList: array containing the list of year sub-folders
  - $match      : regular expression to use when parsing the `tarchive` library
                  folder

RETURNS: the list of matching DICOM archives into a dereferenced array

### selectTarchives($dbh, $tarchiveLibraryDir)

Function that will select the `ArchiveLocation` and `md5sumArchive` fields of the
tarchive table for all entries stored in that table.

INPUTS:
  - $dbh               : the database handle object
  - $tarchiveLibraryDir: tarchive library directory (e.g. /data/project/data/tarchive)

RETURNS:
    - \\%tarchiveInfo: hash of the DICOM archives found in the database, with the
                      `ArchiveLocation` as keys and `md5sum` information as values

### getTarchiveBasename($tarchive)

Function that will determine the DICOM archive basename from the `ArchiveLocation`
stored in the database. It will, among other things, get rid of the `_digit part`
that was inserted in the past by the `tarchiveLoader.pl`.

INPUT: `ArchiveLocation` that was stored in the `tarchive` table of the database.

RETURNS: the DICOM archive basename to use when looking for duplicate DICOM archives
         in the `tarchive` library directory of the filesystem

### identifyDuplicates($tarchive\_db, $tarchivesList\_db, $tarFileList)

Function that will identify the duplicate DICOM archives present in the filesystem.

INPUTS:
  - $tarchive\_db     : DICOM archive file stored in the database's `tarchive` table
  - $tarchivesList\_db: hash with the list of DICOM archives locations stored in the
                       database (keys of the hash) and their corresponding md5sum
                       (values of the hash)
  - tarFileList      : list of DICOM archives found in the filesystem that match
                       the basename of `$tarchive_db`

RETURNS:
  - Undef: if did not find any DICOM archive on the filesystem matching the file
           stored in the database
  - @duplicateTarFiles: list of duplicate DICOM archive found in the filesystem
  - $realTarFileFound : path to the actual DICOM archive that matches the one in
                        the `tarchive` table of the database

### removeDuplicates($duplicateTars)

Function that removes the duplicate DICOM archives stored in dereferenced
array `$duplicateTars` from the filesystem.

INPUT: list of the duplicate DICOM archives found on the filesystem

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

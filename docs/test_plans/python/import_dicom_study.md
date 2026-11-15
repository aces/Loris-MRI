# LORIS DICOM importer test plan

## Preamble

- The LORIS DICOM importer is a script to import a DICOM study in LORIS.
- The LORIS DICOM importer code and documentation is located in the `loris-bids-importer` package.
- It is advised to take a look at the package README file before starting the tests.
- The `tarchiveLibraryDir` LORIS configuration option should point to an existing directory before starting the tests.

## Testing instructions

### Running the script

Ensure a DICOM study can be imported into LORIS:
```sh
import-dicom-study /path/to/dicom/study
```

### Imported DICOM study

- Ensure the DICOM study is visible in the LORIS DICOM archive module, with a list of all its DICOM files and working download link.
- Ensure the DICOM study is attached to a LORIS session based on its patient identifiers.
- Ensure the DICOM study is present in the LORIS database in the `tarchive_*` tables.
- Ensure the DICOM study archive is present in the LORIS `tarchive` directory.
- Ensure the DICOM study archive contains a `.log` and `.meta`file, and that both their contents look correct.

### Other commands

- Ensure that a DICOM study that is already imported in LORIS can be updated by using the `--update` and `--overwrite` CLI options.
- Ensure the `summarize-dicom-study` script produces a correct looking DICOM study summary.
- Ensure that inserting with `--no-session` leaves the study without a session.

### Errors cases

- Ensure that importing a non-DICOM study file or directory results in an error.
- Ensure that importing a DICOM study that is already in LORIS results in an error.
- Ensure that updating a DICOM study that is not already in LORIS results in an error.

## Testing data

Usable DICOM studies may be found in the `/data/loris/incoming` directory, as well as already archived DICOM studies in the `/data/loris/tarchive` directory (which should then be untarred for testing).

To test the DICOM study importer with an already imported DICOM study, existing data should first be removed from the LORIS database and data directory.

A DICOM study an be removed from the database using the following SQL statement:
```sql
DELETE FROM tarchive WHERE tarchiveID = @id;
```

If foreign keys exist in other tables (like `mri_upload` or `files`), it is advised to set the relevant attributes to `NULL`.

### update\_MincPath\_field($dbh, $table, $id\_field, $file\_field)

Greps all the files present in a given table and updates its location to the file
present in the trashbin subdirectory of the LORIS-MRI data directory.

INPUTS:
  - $dbh            : database handle reference
  - $table\_name     : name of the table to update
  - $id\_field\_name  : name of the ID field of the table
  - $file\_field\_name: name of the field containing the file location in the table

### determine\_MincPath($dbh, $file\_ref, $table\_name, $file\_field\_name)

Determines the new file path of the file to use when updating the violation
tables.

INPUTS:
  - $dbh            : database handle reference
  - $file\_ref       : hash with row information from the violation table
  - $table\_name     : table name used to create the hash $file\_ref
  - $file\_field\_name: file location field name in the violation table

RETURNS:
  - new file path to use to update the violation table
  - undef if the file is in `mri_violations_log` with `Severity`='warning' and
    no entry with the same `SeriesUID` was found in the `files` table

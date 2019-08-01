# NAME

NeuroDB::objectBroker::MriUploadOB -- An object broker for MRI uploads

# SYNOPSIS

    use NeuroDB::Database;
    use NeuroDB::objectBroker::MriUploadOB;
    use TryCatch;

    my $db = NeuroDB::Database->new(
        userName     => 'user',
        databaseName => 'my_db',
        hostName     => 'my_hostname',
        password     => 'pwd'
    );

    try {
        $db->connect();
    } catch(NeuroDB::DatabaseException $e) {
        die sprintf(
            "User %s failed to connect to %s on %s: %s (error code %d)\n",
            'user',
            'my_db',
            'my_hostname',
            $e->errorMessage,
            $e->errorCode
        );
    }

    .
    .
    .

    my $mriUploadOB = NeuroDB::objectBroker::MriUploadOB->new(db => $db);
    my $mriUploadsRef;
    try {
        $mriUploadsRef= $mriUploadOB->getWithTarchive(
            1, '/tmp/my_tarchive.tar.gz', 1
        );
    } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
        die sprintf(
            "Failed to retrieve MRI uploads: %s",
            $e->errorMessage
        );
    }

# DESCRIPTION

This class provides a set of methods to either fetch or insert MRI upload
records. The operations are always performed on database table `mri_upload`.
Each method will throw a `NeuroDB::objectBroker::ObjectBrokerException` if 
the request could not be performed successfully.

## Methods

### new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
`Database` object used to access the database.

INPUT: the database object used to read/modify the `mri_upload` table.

RETURNS: new instance of this class.

### getWithTarchive($isCount, $tarchiveLocation, $isBaseNameMatch)

Fetches the entries in the `mri_upload` table that have a specific archive
location. This method throws a `NeuroDB::objectBroker::ObjectBrokerException`
if the operation could not be completed successfully.

INPUTS:
    - boolean indicating if only a count of the records found is needed
      or the full record properties.
    - path of the archive location.
    - boolean indicating if a match is sought on the full archive name
      or only the basename.

RETURNS: a reference to an array of array references. If `$isCount` is true, then
         `$returnValue->[0]->[0]` will contain the count of records sought. Otherwise
         `$returnValue->[x]->[y]` will contain the value of the yth column (in array
         `@MRI_UPLOAD_FIELDS` for the xth record retrieved.

### insert($valuesRef)

Inserts a new record in the `mri_upload` table with the specified column values.
This method throws a `NeuroDB::objectBroker::ObjectBrokerException` if the operation
could not be completed successfully.

INPUT: a reference to a hash of the values to insert. The hash contains the column
       names and associated record values used during insertion. All the keys of
       `%$valuesRef` must exist in `@MRI_UPLOAD_FIELDS` or an exception will be thrown.

RETURNS: the index of the MRI upload record inserted.

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

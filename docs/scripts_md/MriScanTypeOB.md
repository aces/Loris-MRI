# NAME

NeuroDB::objectBroker::MriScanTypeOB -- An object broker for mri\_scan\_type records

# SYNOPSIS

    use NeuroDB::Database;
    use NeuroDB::objectBroker::MriScanTypeOB;
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

    my $mriScanTypeOB = NeuroDB::objectBroker::MriScanTypeOB->new(db => $db);
    my $mriScanTypeRef;
    try {
        $mriScanTypeRef = $mriScanTypeOB->get(
            0, { ScanType => 'dti' }
        );
    } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
        die sprintf(
            "Failed to retrieve tarchive records: %s",
            $e->errorMessage
        );
    }

# DESCRIPTION

This class provides a set of methods to fetch records from the `mri_scan_type`
table. If an operation cannot be executed successfully, a `NeuroDB::objectBroker::ObjectBrokerException`
will be thrown.

## Methods

### new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
`Database` object used to access the database.

INPUT: the database object used to query the `mri_scan_type` table.

RETURN: new instance of this class.

### get($isCount, $columnValuesRef))
Fetches the entries in the `mri_upload` table that have specific column
values. This method throws a `NeuroDB::objectBroker::ObjectBrokerException`
if the operation could not be completed successfully.
INPUTS:
    - boolean indicating if only a count of the records found is needed
      or the full record properties.
    - reference to a hash array that contains the column values that the MRI records
      should have in order to be part of the result set (key: column name, value: column
      value).

RETURNS: either a count of the records found or a reference to an array of hashes, each 
         hash being an MRI record found, with all the columns set to whatever was found
         in the database.

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

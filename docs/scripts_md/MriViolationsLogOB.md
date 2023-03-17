# NAME

NeuroDB::objectBroker::MriViolationsLogOB -- An object broker for `mri_violations_log` records

# SYNOPSIS

    use NeuroDB::Database;
    use NeuroDB::objectBroker::MriViolationsLogOB;
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

    my $mriViolationsLogOB = NeuroDB::objectBroker::MriViolationsLogOB->new(db => $db);
    my $mriProtocolViolatedScansOBRef;
    try {
        $mriViolationsLogOBRef = $mriViolationsLogOB->getByTarchiveID(
            [ 'TarchiveID' ], 12
        );
    } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
        die sprintf(
            "Failed to retrieve mri_violations_log records: %s",
            $e->errorMessage
        );
    }

# DESCRIPTION

This class provides a set of methods to either fetch records from the `mri_violations_log`
table, insert new entries in it or update existing ones. If an operation cannot
be executed successfully, a `NeuroDB::objectBroker::ObjectBrokerException` is thrown.

## Methods

### new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
`Database` object used to access the database.

INPUT: the database object used to read/modify the `mri_violations_log` table.

RETURN: new instance of this class.

### getWithTarchiveID($tarchiveID)

Fetches the records from the `mri_violations_log` table that have a specific `TarchiveID`.

INPUTS:
    - ID of the tarchive used during the search.

RETURN: a reference to an array of hash references. Every hash contains the values for a given
        row returned by the function call: the key/value pairs contain the name of a column
        (listed in `@MRIVIOLATIONSLOG_FIELDS`) and the value it holds, respectively.
        As an example, suppose array `$r` contains the result of a call to this method with
        `@$fieldsRef` set to `('TarchiveID', 'MincFile'` one would fetch the `MincFile`
        of the 4th record returned using `$r-`\[3\]->{'MincFile'}>.

### insert($valuesRef)

Inserts a new record in the `mri_violations_log` table with the specified column values.
This method throws a `NeuroDB::objectBroker::ObjectBrokerException` if the operation
could not be completed successfully.

INPUT: a reference to a hash of the values to insert. The hash contains the column
       names and associated record values used during insertion. All the keys of
       `%$valuesRef` must exist in `@MRIVIOLATIONSLOG_FIELDS` or an exception will be thrown.

RETURNS: the index of the MRI upload record inserted.

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

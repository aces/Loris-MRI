# NAME

NeuroDB::objectBroker::MriProtocolViolatedScansOB -- An object broker for `mri_protocol_violated_scans` records

# SYNOPSIS

    use NeuroDB::Database;
    use NeuroDB::objectBroker::MriProtocolViolatedScansOB;
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

    my $mriProtocolViolatedScansOB = NeuroDB::objectBroker::MriProtocolViolatedScansOB->new(db => $db);
    my $mriProtocolViolatedScansOBRef;
    try {
        $mriProtocolViolatedScansOBRef = $mriProtocolViolatedScansOB->getByTarchiveID(
            [ 'TarchiveID' ], 12
        );
    } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
        die sprintf(
            "Failed to retrieve mri_protocol_violated_scans records: %s",
            $e->errorMessage
        );
    }

# DESCRIPTION

This class provides a set of methods to either fetch records from the `mri_protocol_violated_scans`
table, insert new entries in it or update existing ones. If an operation cannot
be executed successfully, a `NeuroDB::objectBroker::ObjectBrokerException` is thrown.

## Methods

### new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
`Database` object used to access the database.

INPUT: the database object used to read/modify the `mri_protocol_violated_scans` table.

RETURN: new instance of this class.

### getWithTarchiveID($tarchiveID)

Fetches the records from the `mri_protocol_violated_scans` table that have a specific `TarchiveID`.

INPUTS:
    - ID of the tarchive used during the search.

RETURN: a reference to an array of hash references. Every hash contains the values for a given
        row returned by the function call: the key/value pairs contain the name of a column
        (listed in `@MRIPROTOCOLVIOLATEDSCANS_FIELDS`) and the value it holds, respectively.
        As an example, suppose array `$r` contains the result of a call to this method with
        `@$fieldsRef` set to `('TarchiveID', 'minc_location'` one would fetch the `minc_location`
        of the 4th record returned using `$r-`\[3\]->{'minc\_location'}>.

### insert($valuesRef)

Inserts a new record in the `mri_protocol_violated_scans` table with the specified column values.
This method throws a `NeuroDB::objectBroker::ObjectBrokerException` if the operation
could not be completed successfully.

INPUT: a reference to a hash of the values to insert. The hash contains the column
       names and associated record values used during insertion. All the keys of
       `%$valuesRef` must exist in `@MRIPROTOCOLVIOLATEDSCANS_FIELDS` or an exception will be thrown.

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

# NAME

NeuroDB::objectBroker::TarchiveOB -- An object broker for `tarchive` records

# SYNOPSIS

    use NeuroDB::Database;
    use NeuroDB::objectBroker::TarchiveOB;
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

    my $tarchiveOB = NeuroDB::objectBroker::TarchiveOB->new(db => $db);
    my $tarchivesRef;
    try {
        $tarchivesRef = $tarchiveOB->getByTarchiveLocation(
            [ 'TarchiveID' ], '/tmp/my_tarchive.tar.gz'
        );
    } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
        die sprintf(
            "Failed to retrieve tarchive records: %s",
            $e->errorMessage
        );
    }

# DESCRIPTION

This class provides a set of methods to either fetch records from the `tarchive`
table, insert new entries in it or update existing ones. If an operation cannot
be executed successfully, a `NeuroDB::objectBroker::ObjectBrokerException` is thrown.

## Methods

### new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
`Database` object used to access the database.

INPUT: the database object used to read/modify the `tarchive` table.

RETURN: new instance of this class.

### getByTarchiveLocation($tarchiveLocation)

Fetches the records from the `tarchive` table that have a specific archive location.

INPUTS:
    - path of the archive used during the search.

RETURN: a reference to an array of hash references. Every hash contains the values for a given 
        row returned by the function call: the key/value pairs contain the name of a column 
        (listed in `@TARCHIVE_FIELDS`) and the value it holds, respectively.
        As an example, suppose array `$r` contains the result of a call to this method with 
        `@$fieldsRef` set to `('TarchiveID', 'SourceLocation'` one would fetch the `TarchiveID` 
        of the 4th record returned using `$r-`\[3\]->{'TarchiveID'}>.

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

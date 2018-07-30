# NAME

NeuroDB::objectBroker::PSCOB -- An object broker for records stored in table `psc`.

# SYNOPSIS

    use NeuroDB::Database;
    use NeuroDB::objectBroker::PSCOB;
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

    my $pscOB = NeuroDB::objectBroker::PSCOB->new(db => $db);
    my $pscRef;
    try {
        $pscRef = $pscOB->get(
            { Alias => 'DCC' }
        );
    } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
        die sprintf(
            "Failed to retrieve psc records: %s",
            $e->errorMessage
        );
    }

# DESCRIPTION

This class provides a set of methods to fetch records from the `psc`
table. If an operation cannot be executed successfully, a `NeuroDB::objectBroker::ObjectBrokerException`
will be thrown. See the documentation for `GetRole` and `InsertRole` for information on how to perform
basic `INSERT`/`SELECT` operations using this object broker.

## Methods

### new(db => $db) >> (constructor inherited from `ObjectBroker`)

Create a new instance of this class. The only parameter to provide is the
`Database` object used to access the database.

INPUT: the database object used to query the `psc` table.

RETURN: new instance of this class.

### getTableName()

Gets the name of the database table with which this object broker interacts.

INPUT: None

RETURN: name of the database table with which this object broker interacts.

### getColumnNames()

Gets the column names for table psc.

INPUT: None

RETURN: Column names for table psc.

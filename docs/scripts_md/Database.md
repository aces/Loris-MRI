# NAME

NeuroDB::Database -- Provides a set of methods to run SQL statements on a database

# SYNOPSIS

    use NeuroDB::Database;
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

    try {
        $db->pselect(
            'SELECT * FROM candidate WHERE pscid = ?', 'MTL135'
        );
    } catch(NeuroDB::DatabaseException $e) {
        die sprintf(
            "SELECT on candidate table failed: %s (error code=%d)",
            $e->errorMessage,
            $e->errorCode
        );
    }

# DESCRIPTION

This class provides the basic `SELECT`, `INSERT`, `UPDATE` and `DELETE` methods
for all object brokers. The methods of this class should only be used by
the object brokers themselves (except `new` for creating a new database
instance and `connect`). Scripts and 'non-broker' classes that need access
to the database should rely on an appropriate object broker class to handle
the requests.

## Methods

### `new(userName => $u, databaseName => $d, hostname => $h, password => $pwd, port =>$port)`  (constructor)

Create a new instance of this class, without actually trying to connect
to the database specified. All parameters are required except `port`, which
defaults to 3306 if not specified. If the user name, database name or host
name are the empty string, the constructor will call `die`.

INPUTS:
  - name of the user for the (upcoming) connection.
  - name of the database.
  - name of the host on which the database resides.
  - password for the (upcoming) connection.
  - port used for the (upcoming) connection (defaults to 3306 if not provided).

RETURN: new instance of this class.

### `connect()`

Attempts to connect to the database using the connection parameters passed
at construction time. This method will throw a `DatabaseException` if the
connection could not be established.

### `pselect($query, @args)`

Executes a `SELECT` query on the database. This method will first `prepare`
the statement passed as parameter before sending the request to the database.

INPUTS: 
  - `SELECT` query to execute (containing the argument placeholders if any).
  - list of arguments to replace the placeholders with.

RETURN: a reference to the array of records found. Each record is in fact a
        reference to the list of values for the columns selected.

### `insertOne($tableName, $valuesRef)`

Inserts one record in a given database table with the specified column values.
This method will throw a `DatabaseException` if the record cannot be inserted.

INPUTS: 
  - name of the table in which to insert the record.
  - reference to a hash array describing the column names and their values
    for the given record.

RETURN: the ID of the record inserted.

### `insert($tableName, $columnNamesRef, $valuesRef)`

Inserts one record in a given database table with the specified column values.
This method will throw a `DatabaseException` if the record cannot be inserted.

INPUTS: 
  - name of the table in which to insert the record.
  - reference to an array containing the names of the columns whose values
    will be modified by this `INSERT` statement.
  - reference to an array of array references. This "matrix" contains the
    values of each column for each record.

### `disconnect()`

Terminates the connection previously instantiated to the database if a 
connection was previously established.

### `DESTROY()`

Object destructor: terminates the connection previously instantiated to the
database (if any).

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

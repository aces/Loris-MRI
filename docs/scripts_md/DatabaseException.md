# NAME

NeuroDB::DatabaseException -- Exception for database related errors.

# SYNOPSIS

    use NeuroDB::DatabaseException;

    .
    .
    .

    NeuroDB::DatabaseException->throw(
        statement    => 'SELECT * from Foo WHERE x=? AND y=?',
        args         => [1, 2],
        errorCode    => $DBI::err,
        errorMessage => $DBI::errstr
    );

# DESCRIPTION

This class is the base class for database-related exceptions. You use this
class by calling the `throw` method with the specified parameters (all of
which are required). This will build a new instance of this class and throw
it as expected. The throw method of this class will call `die` if the error
code is zero and the error message is defined or if the error code is not
0 and the error message is undefined.

### `toString()`

Default representation of this exception when used in a string context.
Among other things, the returned string will be used for uncaught exceptions
that make a script die. Note that the returned string can be useful for debugging
purposes when trying to diagnose why a particular SQL statement did not execute
successfully.

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

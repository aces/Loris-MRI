# NAME

NeuroDB::UnexpectedValueException -- Exception used to signal that an unexpected value was found during program execution.

# SYNOPSIS

    use NeuroDB::UnexpectedValueException;

    .
    .
    .

    NeuroDB::UnexpectedValueException->throw(
        errorMessage => "Scan ID should be a number"
    );

# DESCRIPTION

This class is used when an unexpected value is obtained during execution of a command, like
a database query, reading text from a file, etc... 

### `toString()`

Default representation of this exception when used in a string context.
Among other things, the returned string will be used for uncaught exceptions
that make a script die. 

RETURN: string representation of this exception.

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

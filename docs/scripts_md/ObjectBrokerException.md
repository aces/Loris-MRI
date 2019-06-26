# NAME

NeuroDB::objectBroker::ObjectBrokerException -- Exception for all unexpected errors
related to an object broker

# SYNOPSIS

    use NeuroDB::objectBroker::ObjectBrokerException;

    .
    .
    .

    NeuroDB::objectBroker::ObjectBrokerException->throw(
        errorMessage => 'Failed to perform the requested task'
    );

# DESCRIPTION

This class is the base class for object broker related exceptions. All object
brokers should use this class to report unexpected errors/behaviour. You use this
class by calling the `throw` method with a specific error message (passed
as argument). This will build a new instance of this class and throw
it as expected.

### `toString()`

Default string representation of this exception: its associated error
message.

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

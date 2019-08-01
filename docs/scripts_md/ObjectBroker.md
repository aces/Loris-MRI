# NAME

NeuroDB::objectBroker::ObjectBroker -- Superclass for all object brokers.

# DESCRIPTION

This class provides the set of methods common to all object brokers. Any object broker used 
by the MRI pipeline or associated scripts should extend this class.

## Methods

### new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
`Database` object used to access the database.

INPUT: the database object used to perform queries on the database tables.

RETURN: new instance of this class.

# NAME

NeuroDB::objectBroker::InsertRole -- A role for basic `INSERT` operations on the database.

# DESCRIPTION

This class provides a generic method to insert a given record in the database.
If an operation cannot be executed successfully, a `NeuroDB::objectBroker::ObjectBrokerException`
will be thrown. All classes that use this role must implement methods `getTableName()`, `getColumnNames()` and `db()`.

## Methods

### insertOne($valuesRef)

Inserts the record with the properties passed as argument in the table whose name is returned
by `getTableName()`.

INPUTS:
   - reference to a hash array that contains the column values for the record to insert.
     Each key must be a valid field (i.e that exists in the array returned by `getColumnNames()`
     and each value is the value for the given field. Use `undef` to set a field to `NULL`.

RETURNS: 
   - the ID of the inserted record if the operation succeeded. A <NeuroDB::objectBroker::ObjectBrokerException>
     will be thrown otherwise.

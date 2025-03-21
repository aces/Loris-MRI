# NAME

NeuroDB::objectBroker::GetRole -- A role for basic SELECT operations on the database

# SYNOPSIS

# DESCRIPTION

This class provides methods used to accomplish basic `SELECT` operations on the database.
It allows the retrieval of records using a simple `WHERE` clause of the form 
`WHERE constraint_1 AND constraint_2 AND ... AND constraint_n`.
Subparts of the `WHERE` clause can only be combined with `AND` (`OR` is not supported). 
Each subpart of the `WHERE` clause specifies that a field must be either equal to a given 
value, not equal to a given value, NULL or NOT NULL. 

Classes using this role must implement methods `getColumnNames()`, `getTableName()` and `db()`.

## Methods

### get($isCount, $columnValuesRef)

Fetches the records in the table whose name is returned by method `getTableName()` that satisfy
specific constraints. 

Note that this method is private.

INPUTS:
   - boolean indicating if only a count of the records found is needed
     or the full record properties.
   - reference to a hash array that contains the column values that the records
     should have in order to be part of the result set (key: column name, value: column
     value).

RETURNS: 
   - a reference to an array of hash references. Every hash contains the values
     for a given row returned by the method call: the key/value pairs contain
     the name of a column (see `@MRI_SCAN_TYPE_FIELDS`) and the value it 
     holds, respectively. As an example, suppose array `$r` contains the result of a
     given call to this function. One would fetch the `Scan_type` of the 2nd record 
     returned using `$r->[1]->{'Scan_type'}`.
     If the method is called with `$isCount` set to true, then it will return
     a reference to an array containing a single hash reference, its unique key being 
     `'COUNT(*)'` with the associated value set to the selected count.

### addWhereEquals($columnValuesRef, $k, $whereRef, $valsRef)

Gets the string representation of a constraint of the form `field=value` and adds it
to the current set of `WHERE` clauses. Note that constraints specifying that a field 
must be NULL will be properly translated to `field IS NULL` (not `field=NULL`).

INPUTS:
   - Reference on the hash of all field constraints.
   - Name of the field for which a string representation is sought.
   - Reference on the array of all constraints (in string form).
   - Reference on the array of values each field in `$columnValuesRef` must be
     equal or not equal to.

RETURNS: 
   - Nothing (adds an element to `@$whereRef`).

### addWhereFunction($columnValuesRef, $k, $whereRef, $valsRef)

Gets the string representation of a constraint that uses an SQL function or operator.
Currently, only the operator `NOT` (i.e. field `NOT` equal to a given value or `NOT NULL`) is 
supported.

INPUTS:
   - Reference on the hash of all field constraints
   - Name of the field for which a string representation is sought.
   - Reference on the array of all constraints (in string form)
   - Reference on the array of values each field in `$columnValuesRef` must be
     equal or not equal to.

RETURNS: 
   - Nothing. Updates arrays `@$whereRef` (and `@$valsRef` if necessary).

### addWhereNotEquals($columnValuesRef, $k, $whereRef, $valsRef)

Gets the string representation of a constraint of the form `field != value` and adds it to
the current set of `WHERE` clauses. Note that constraints specifying that a field must not be NULL 
will be properly translated to `field IS NOT NULL` (not `field!=NULL`).

INPUTS:
   - Reference on the hash of all field constraints
   - Name of the field for which a string representation is sought.
   - Reference on the array of all constraints (in string form)
   - Reference on the array of values each field in `$columnValuesRef` must be
     equal or not equal to.

RETURNS: 
   - Nothing. Updates arrays `@$whereRef` (and `@$valsRef` if necessary).

### get($columnValuesRef)

Fetches the records in the table whose name is returned by method `getTableName()` that satisfy
specific constraints. 

INPUTS:
   - reference to a hash array that contains the constraints on the column values that the records
     should have in order to be part of the result set. The keys are column names and
     the values are the constraints on each column. Each constraint can be expressed as
     a single value or a reference to a hash (this hash describes a constraint involving an
     SQL function or operator other than '='). Examples of a valid set of constraints:

     {  
       Field1 => 'Value1',
       Field2 => { NOT => 3 },
       Field3 => undef
     }
      

RETURNS: 
   - a reference to an array of hash references. Every hash contains the values
     for a given row returned by the method call: the key/value pairs contain
     the name of a column (as listed by `getColumnNames()`) and the value it 
     holds, respectively. As an example, suppose array `$r` contains the result of a
     given call to this function. One would fetch the `Scan_type` of the 2nd record 
     returned using `$r->[1]->{'Scan_type'}`.

### getCount($columnValuesRef)

Fetches the number of records in the table whose name is returned by method `getTableName()` 
that satisfy specific constraints. 

INPUTS:
   - reference to a hash array that contains the constraints on the column values that the records
     should have in order to be part of the result set. The keys are column names and
     the values are the constraints on each column. Each constraint can be expressed as
     a single value or a reference to a hash (this hash describes a constraint involving an
     SQL function or operator other than '='). Examples of a valid set of constraints:

     {  
       Field1 => 'Value1',
       Field2 => { NOT => 3 },
       Field3 => undef
     }
      

RETURNS: 
   - the number of records found.

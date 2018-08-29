package NeuroDB::objectBroker::GetRole;

=pod

=head1 NAME

NeuroDB::objectBroker::GetRole -- A role for basic SELECT operations on the database

=head1 SYNOPSIS

=head1 DESCRIPTION

This class provides methods used to accomplish basic C<SELECT> operations on the database.
It allows the retrieval of records using a simple C<WHERE> clause of the form 
C<WHERE constraint_1 AND constraint_2 AND ... AND constraint_n>.
Subparts of the C<WHERE> clause can only be combined with C<AND> (C<OR> is not supported). 
Each subpart of the C<WHERE> clause specifies that a field must be either equal to a given 
value, not equal to a given value, NULL or NOT NULL. 

Classes using this role must implement methods C<getColumnNames()>, C<getTableName()> and C<db()>.

=head2 Methods

=cut

use Moose::Role;

requires 'getColumnNames';
requires 'getTableName';
requires 'db';

use NeuroDB::objectBroker::ObjectBrokerException;

use TryCatch;

=pod

=head3 get($isCount, $columnValuesRef)

Fetches the records in the table whose name is returned by method C<getTableName()> that satisfy
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
     the name of a column (see C<@MRI_SCAN_TYPE_FIELDS>) and the value it 
     holds, respectively. As an example, suppose array C<$r> contains the result of a
     given call to this function. One would fetch the C<Scan_type> of the 2nd record 
     returned using C<< $r->[1]->{'Scan_type'} >>.
     If the method is called with C<$isCount> set to true, then it will return
     a reference to an array containing a single hash reference, its unique key being 
     C<'COUNT(*)'> with the associated value set to the selected count.
     
=cut

my $getRef = sub {
	my($self, $isCount, $columnValuesRef) = @_;

    my @where;
    my @vals;
    
    if (%$columnValuesRef) {
        foreach my $k (keys %$columnValuesRef) {
			# Field must be in array of known column names. Throw an exception
			# otherwise
            if(!grep($k eq $_, $self->getColumnNames())) {
                NeuroDB::objectBroker::ObjectBrokerException->throw(
                    errorMessage => sprintf(
                        "Get records from table %s failed: unknown field %s",
                        $self->getTableName(),
                        $k
                    )
                );
            }
            
            # Update @where and @vals with the current constraint in %$columnValuesRef
            my $val = $columnValuesRef->{$k};
            my $valType = ref($val);
            if ($valType eq '') { 
				$self->addWhereEquals(  $columnValuesRef, $k, \@where, \@vals); 
		    }
		    elsif ($valType eq 'HASH') { 
				$self->addWhereFunction($columnValuesRef, $k, \@where, \@vals); 
		    }
			else {
                NeuroDB::objectBroker::ObjectBrokerException->throw(
                    errorMessage => sprintf(
                        "Unsupported value type for get call on table %s: %s",
                        $self->getTableName(),
                        $valType
                    )
                );
	        }
        }
	}

    my $select = $isCount ? 'COUNT(*)' : join(',', $self->getColumnNames());

    # Get the query in string form
    my $query = sprintf("SELECT %s FROM %s", $select, $self->getTableName());
    $query .= sprintf(' WHERE %s', join(' AND ', @where)) if @where;

    # Run the query and return the result
    try {
        return $self->db->pselect($query, @vals);
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to get records from table %s. Reason:\n%s",
                $self->getTableName(),
                $e
            )
        );
    }
};

=pod

=head3 addWhereEquals($columnValuesRef, $k, $whereRef, $valsRef)

Gets the string representation of a constraint of the form C<field=value> and adds it
to the current set of C<WHERE> clauses. Note that constraints specifying that a field 
must be NULL will be properly translated to C<field IS NULL> (not C<field=NULL>).

INPUTS:
   - Reference on the hash of all field constraints.
   - Name of the field for which a string representation is sought.
   - Reference on the array of all constraints (in string form).
   - Reference on the array of values each field in C<$columnValuesRef> must be
     equal or not equal to.
      
RETURNS: 
   - Nothing (adds an element to C<@$whereRef>).

=cut

sub addWhereEquals {
	my($self, $columnValuesRef, $k, $whereRef, $valsRef) = @_;
	
	if(defined $columnValuesRef->{$k}) {
        push(@$whereRef, "$k=?");
	    push(@$valsRef, $columnValuesRef->{$k});
	} else {
        push(@$whereRef, "$k IS NULL");
    }
}

=pod

=head3 addWhereFunction($columnValuesRef, $k, $whereRef, $valsRef)

Gets the string representation of a constraint that uses an SQL function or operator.
Currently, only the operator C<NOT> (i.e. field C<NOT> equal to a given value or C<NOT NULL>) is 
supported.

INPUTS:
   - Reference on the hash of all field constraints
   - Name of the field for which a string representation is sought.
   - Reference on the array of all constraints (in string form)
   - Reference on the array of values each field in C<$columnValuesRef> must be
     equal or not equal to.
      
RETURNS: 
   - Nothing. Updates arrays C<@$whereRef> (and C<@$valsRef> if necessary).

=cut

sub addWhereFunction {
	my($self, $columnValuesRef, $k, $whereRef, $valsRef) = @_;

    # Make sure hash array %{ $columnValueRef->{$k} } has exactly one key/value pair
    if(keys %{ $columnValuesRef->{$k} } != 1) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to get records from table %s. Hash array for constraint "
                    . "on column %s should contain exacly one key/value pair.",
                $self->getTableName(),
                $k
            )
        );
	}
	
	# Make sure key of %{ $columnValuesRef->{$k} } is 'NOT'
	my($fname, $args) = each %{ $columnValuesRef->{$k} };
	if($fname eq'NOT') { $self->addWhereNotEquals($columnValuesRef, $k, $whereRef, $valsRef); }
    else {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => "Failed to get records from table %s. Unsupported "
                . "function $fname for constraint on column $k"
        );
    }	
}

=pod

=head3 addWhereNotEquals($columnValuesRef, $k, $whereRef, $valsRef)

Gets the string representation of a constraint of the form C<field != value> and adds it to
the current set of C<WHERE> clauses. Note that constraints specifying that a field must not be NULL 
will be properly translated to C<field IS NOT NULL> (not C<field!=NULL>).

INPUTS:
   - Reference on the hash of all field constraints
   - Name of the field for which a string representation is sought.
   - Reference on the array of all constraints (in string form)
   - Reference on the array of values each field in C<$columnValuesRef> must be
     equal or not equal to.
      
RETURNS: 
   - Nothing. Updates arrays C<@$whereRef> (and C<@$valsRef> if necessary).

=cut
sub addWhereNotEquals {
	my($self, $columnValuesRef, $k, $whereRef, $valsRef) = @_;
	
	if(defined $columnValuesRef->{$k}->{'NOT'}) {
        push(@$whereRef, "$k!=?");
	    push(@$valsRef, $columnValuesRef->{$k}->{'NOT'});
	} else {
        push(@$whereRef, "$k IS NOT NULL");
    }	
}

=pod

=head3 get($columnValuesRef)

Fetches the records in the table whose name is returned by method C<getTableName()> that satisfy
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
     the name of a column (as listed by C<getColumnNames()>) and the value it 
     holds, respectively. As an example, suppose array C<$r> contains the result of a
     given call to this function. One would fetch the C<Scan_type> of the 2nd record 
     returned using C<< $r->[1]->{'Scan_type'} >>.
=cut

sub get {
	my($self, $columnValuesRef) = @_;
	
	return $getRef->($self, 0, $columnValuesRef);
}

=pod

=head3 getCount($columnValuesRef)

Fetches the number of records in the table whose name is returned by method C<getTableName()> 
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

=cut

sub getCount {
	my($self, $columnValuesRef) = @_;
	
	my $results = $getRef->($self, 1, $columnValuesRef);
	return $results->[0]->{'COUNT(*)'};
}



1;

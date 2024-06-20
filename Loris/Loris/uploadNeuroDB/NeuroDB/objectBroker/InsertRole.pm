package NeuroDB::objectBroker::InsertRole;

=pod

=head1 NAME

NeuroDB::objectBroker::InsertRole -- A role for basic C<INSERT> operations on the database.

=head1 DESCRIPTION

This class provides a generic method to insert a given record in the database.
If an operation cannot be executed successfully, a C<NeuroDB::objectBroker::ObjectBrokerException>
will be thrown. All classes that use this role must implement methods C<getTableName()>, C<getColumnNames()> and C<db()>.

=head2 Methods

=cut

use Moose::Role;

requires 'getColumnNames';
requires 'getTableName';
requires 'db';

use NeuroDB::DatabaseException;
use NeuroDB::objectBroker::ObjectBrokerException;

use TryCatch;

=pod

=head3 insertOne($valuesRef)

Inserts the record with the properties passed as argument in the table whose name is returned
by C<getTableName()>.

INPUTS:
   - reference to a hash array that contains the column values for the record to insert.
     Each key must be a valid field (i.e that exists in the array returned by C<getColumnNames()>
     and each value is the value for the given field. Use C<undef> to set a field to C<NULL>.
      
RETURNS: 
   - the ID of the inserted record if the operation succeeded. A <NeuroDB::objectBroker::ObjectBrokerException>
     will be thrown otherwise.

=cut

sub insertOne {
    my($self, $valuesRef) = @_;

    # Make sure %$valuesRef is not empty
    if(!keys %$valuesRef) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Insertion of record in table %s failed: no values specified",
                $self->getTableName()
            )
        );
    }

    # Make sure all keys of %$valuesRef exist in the array returned by
    # getColumnNames()
    foreach my $v (keys %$valuesRef) {
        if(!grep($v eq $_, $self->getColumnNames())) {
            NeuroDB::objectBroker::ObjectBrokerException->throw(
                errorMessage => sprintf(
                    "Insertion of record in table %s failed: invalid field %s",
                    $self->getTableName(),
                    $v
               )
            );
        }
    }

    # Insert the record and return its ID
    try {
        my @results = $self->db->insertOne($self->getTableName(), $valuesRef);
        return $results[0];
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to insert record in table %s:\n%s",
                $self->getTableName(),
                $e
            )
        );
    }
}

1;

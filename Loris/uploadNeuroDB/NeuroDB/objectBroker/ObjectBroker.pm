package NeuroDB::objectBroker::ObjectBroker;

=pod

=head1 NAME

NeuroDB::objectBroker::ObjectBroker -- Superclass for all object brokers.

=head1 DESCRIPTION

This class provides the set of methods common to all object brokers. Any object broker used 
by the MRI pipeline or associated scripts should extend this class.

=head2 Methods

=cut

use Moose;

use NeuroDB::Database;

=pod

=head3 new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
C<Database> object used to access the database.

INPUT: the database object used to perform queries on the database tables.

RETURN: new instance of this class.

=cut

has 'db' => (is  => 'rw', isa => 'NeuroDB::Database', required => 1);

1;

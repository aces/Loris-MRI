package NeuroDB::DatabaseException;

=pod

=head1 NAME

NeuroDB::DatabaseException -- Exception for database related errors.

=head1 SYNOPSIS

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

=head1 DESCRIPTION

This class is the base class for database-related exceptions. You use this
class by calling the C<throw> method with the specified parameters (all of
which are required). This will build a new instance of this class and throw
it as expected. The throw method of this class will call C<die> if the error
code is zero and the error message is defined or if the error code is not
0 and the error message is undefined.

=cut

use Moose;
with 'Throwable';

has 'statement'    => (is  => 'ro', isa => 'Str'            , required => 1);

has 'args'         => (is  => 'ro', isa => 'Maybe[ArrayRef]', required => 1);

has 'errorCode'    => (is  => 'ro', isa => 'Maybe[Int]'     , required => 1);

has 'errorMessage' => (is  => 'ro', isa => 'Maybe[Str]'     , required => 1);

sub BUILD {
    my $self = shift;

    if($self->errorCode == 0 && defined($self->errorMessage)) {
        die "Cannot have a DatabaseTransactionResult with " .
            "a zero error code and a non-empty error message";
    }

    if($self->errorCode != 0 && !defined($self->errorMessage)) {
        die "Cannot have a DatabaseTransactionResult with " .
            "a non-zero error code and an empty error message";
    }
}

1;

package NeuroDB::objectBroker::ObjectBrokerException;

=pod

=head1 NAME

NeuroDB::objectBroker::ObjectBrokerException -- Exception for all unexpected errors
related to an object broker

=head1 SYNOPSIS

  use NeuroDB::objectBroker::ObjectBrokerException;

  .
  .
  .

  NeuroDB::objectBroker::ObjectBrokerException->throw(
      errorMessage => 'Failed to perform the requested task'
  );

=head1 DESCRIPTION

This class is the base class for object broker related exceptions. All object
brokers should use this class to report unexpected errors/behaviour. You use this
class by calling the C<throw> method with a specific error message (passed
as argument). This will build a new instance of this class and throw
it as expected.

=cut

use Moose;
with 'Throwable';

use overload '""' => 'toString';

has 'errorMessage' => (is  => 'ro', isa => 'Str', required => 1);

=pod

=head3 C<toString()>

Default string representation of this exception: its associated error
message.

=cut
sub toString {
    my $self = shift;

    my $msg = sprintf("ERROR: %s", $self->errorMessage);
    $msg .= "\n" unless $msg =~ /\n/;
    
    return $msg;
};

1;
1;

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
brokers should use this class si report unexpected errors/behaviour. You use this
class by calling the C<throw> method with a specific error message (passed
as argument). This will build a new instance of this class and throw 
it as expected. 

=cut

use Moose;
with 'Throwable';

has 'errorMessage' => (is  => 'ro', isa => 'Str', required => 1);

1;

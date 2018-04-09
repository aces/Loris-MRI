package NeuroDB::UnexpectedValueException;

=pod

=head1 NAME

NeuroDB::UnexpectedValueException -- Exception used to signal that an unexpected value was found
     during program execution.

=head1 SYNOPSIS

  use NeuroDB::UnexpectedValueException;

  .
  .
  .

  NeuroDB::UnexpectedValueException->throw(
      errorMessage => "Scan ID should be a number"
  );

=head1 DESCRIPTION

This class is used when an unexpected value is obtained during execution of a command, like
a database query, reading text from a file, etc... 

=cut

use Moose;
with 'Throwable';

use overload '""' => 'toString';

has 'errorMessage' => (is  => 'ro', isa => 'Str', required => 1);

=pod

=head3 C<toString()>

Default representation of this exception when used in a string context.
Among other things, the returned string will be used for uncaught exceptions
that make a script die. Note that the returned string can be useful for debugging
purposes when trying to diagnose why a particular SQL statement did not execute
successfully.

=cut
sub toString {
    my $self = shift;

    return "$self->{errorMessage}\n";
};

1;

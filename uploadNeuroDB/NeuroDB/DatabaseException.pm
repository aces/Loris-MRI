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

use overload '""' => 'toString';

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

    my $toString;
    
    # For anything other than a connection error
    if($self->statement =~ /^(select|insert|update|delete)/i) {
		$toString = "The following database commands failed:\n";
		# Write the statement used to prepare $self->statement
		# Make sure that single quotes are escaped the interpolating $self->statement
        my $formattedStatement = $self->statement;
        $formattedStatement =~ s#'#\\'#g;
        $toString .= sprintf("\tPREPARE s FROM '%s';\n", $formattedStatement);
        
        # Write the statement that sets the MySQL variables and values foreach
        if(@{$self->args} ) {
			my @definedArgs = grep(defined $_, @{$self->args});
			map { $_ =~ s#'#\\'#g } @definedArgs;
		    $toString .= sprintf(
		        "\tSET %s;\n",
		        join(',', map { "\@x$_='$definedArgs[$_-1]'" } 1..@definedArgs)
		    );
		}
		
		# Write EXECUTE statement 
		$toString .= "\tEXECUTE s";
		$toString .= sprintf(
		    " USING %s",
		    join(',', map { "\@x$_" } 1..@{ $self->args })
		);
		$toString .= ";\n";
		$toString .= sprintf(
		    "Error obtained:%s (error code %s)\n",
		    $self->errorMessage,
		    $self->errorCode 
		);
	}
	# For connection errors
    else {
		$toString = sprintf(
		    "Connection command '%s' failed\nError returned: %s (error code %s)\n",
		    $self->statement,
		    $self->errorMessage,
		    $self->errorCode,
		)
	}

    return $toString;
};

1;


__END__


=pod

=head1 TO DO

Nothing planned.

=head1 BUGS

None reported.

=head1 COPYRIGHT AND LICENSE

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

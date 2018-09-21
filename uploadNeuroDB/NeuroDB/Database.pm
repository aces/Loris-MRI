package NeuroDB::Database;

=pod

=head1 NAME

NeuroDB::Database -- Provides a set of methods to run SQL statements on a database

=head1 SYNOPSIS

  use NeuroDB::Database;
  use TryCatch;

  my $db = NeuroDB::Database->new(
      userName     => 'user',
      databaseName => 'my_db',
      hostName     => 'my_hostname',
      password     => 'pwd'
  );

  try {
      $db->connect();
  } catch(NeuroDB::DatabaseException $e) {
      die sprintf(
          "User %s failed to connect to %s on %s: %s (error code %d)\n",
          'user',
          'my_db',
          'my_hostname',
          $e->errorMessage,
          $e->errorCode
      );
  }

  .
  .
  .

  try {
      $db->pselect(
          'SELECT * FROM candidate WHERE pscid = ?', 'MTL135'
      );
  } catch(NeuroDB::DatabaseException $e) {
      die sprintf(
          "SELECT on candidate table failed: %s (error code=%d)",
          $e->errorMessage,
          $e->errorCode
      );
  }

=head1 DESCRIPTION

This class provides the basic C<SELECT>, C<INSERT>, C<UPDATE> and C<DELETE> methods
for all object brokers. The methods of this class should only be used by
the object brokers themselves (except C<new> for creating a new database
instance and C<connect>). Scripts and 'non-broker' classes that need access
to the database should rely on an appropriate object broker class to handle
the requests.

=head2 Methods

=cut

use Moose;
use MooseX::Privacy;
use DBI;
use TryCatch;

use constant DEFAULT_DB_PORT => 3306;

=pod

=head3 C<< new(userName => $u, databaseName => $d, hostname => $h, password => $pwd, port =>$port) >>  (constructor)

Create a new instance of this class, without actually trying to connect
to the database specified. All parameters are required except C<port>, which
defaults to 3306 if not specified. If the user name, database name or host
name are the empty string, the constructor will call C<die>.

INPUTS:
  - name of the user for the (upcoming) connection.
  - name of the database.
  - name of the host on which the database resides.
  - password for the (upcoming) connection.
  - port used for the (upcoming) connection (defaults to 3306 if not provided).

RETURN: new instance of this class.

=cut

has 'userName'     => (is  => 'ro', isa => 'Str', required => 1);

has 'databaseName' => (is  => 'ro', isa => 'Str', required => 1);

has 'hostName'     => (is  => 'ro', isa => 'Str', required => 1);

has 'password'     => (is  => 'ro', isa => 'Str', required => 1);

has 'port'         => (is  => 'ro', isa => 'Int', default => DEFAULT_DB_PORT);

has 'dbh'          => (is  => 'rw', init_arg => undef, traits => [qw/Private/]);

sub BUILD {
    my $self = shift;

    die "User name cannot be the empty string.\n"     if $self->userName     eq '';
    die "Database name cannot be the empty string.\n" if $self->databaseName eq '';
    die "Host name cannot be the empty string.\n"     if $self->hostName     eq '';
}

=pod

=head3 C<connect()>

Attempts to connect to the database using the connection parameters passed
at construction time. This method will throw a C<DatabaseException> if the
connection could not be established.

=cut

sub connect {
    my $self = shift;

    my $connectStatement = sprintf(
         "DBI:mysql:database=%s;host=%s;port=%d;",
         $self->databaseName,
         $self->hostName,
         $self->port
    );

    try {
        $self->dbh(
            DBI->connect(
                $connectStatement,
                $self->userName,
                $self->password,
                { PrintError => 0, RaiseError => 1, AutoCommit => 1 }
            )
        );
    } catch {
        NeuroDB::DatabaseException->throw(
            statement    => $connectStatement,
            args         => [],
            errorCode    => $DBI::err,
            errorMessage => $DBI::errstr
        );
    }
}

=pod

=head3 C<pselect($query, @args)>

Executes a C<SELECT> query on the database. This method will first C<prepare>
the statement passed as parameter before sending the request to the database.

INPUTS: 
  - C<SELECT> query to execute (containing the argument placeholders if any).
  - list of arguments to replace the placeholders with.

RETURN: a reference to the array of records found. Each record is in fact a
        reference to the list of values for the columns selected.
=cut

sub pselect {
    my $self = shift;
    my($query, @args) = @_;

    try {
        my $sth = $self->dbh()->prepare($query);
        $sth->execute(@args);

        return $sth->fetchall_arrayref({});
    } catch {
        NeuroDB::DatabaseException->throw(
            statement    => $query,
            args         => [@args],
            errorCode    => $DBI::err,
            errorMessage => $DBI::errstr
        );
    }
}

=pod

=head3 C<insertOne($tableName, $valuesRef)>

Inserts one record in a given database table with the specified column values.
This method will throw a C<DatabaseException> if the record cannot be inserted.

INPUTS: 
  - name of the table in which to insert the record.
  - reference to a hash array describing the column names and their values
    for the given record.

RETURN: the ID of the record inserted.

=cut

sub insertOne {
    my $self = shift;
    my($tableName, $valuesRef) = @_;

    $self->insert($tableName, [ keys %$valuesRef ], [[ values %$valuesRef]]);

    my $query = "SELECT last_insert_id()";
    try {
        my $sth = $self->dbh()->prepare($query);
        $sth->execute();

        return $sth->fetchrow_array;
    } catch {
        NeuroDB::DatabaseException->throw(
            statement    => $query,
            args         => undef,
            errorCode    => $DBI::err,
            errorMessage => $DBI::errstr
        );
    }
}

=pod

=head3 C<insert($tableName, $columnNamesRef, $valuesRef)>

Inserts one record in a given database table with the specified column values.
This method will throw a C<DatabaseException> if the record cannot be inserted.

INPUTS: 
  - name of the table in which to insert the record.
  - reference to an array containing the names of the columns whose values
    will be modified by this C<INSERT> statement.
  - reference to an array of array references. This "matrix" contains the
    values of each column for each record.

=cut

sub insert {
    my $self = shift;
    my($tableName, $columnNamesRef, $valuesRef) = @_;

    # @allValues = $valuesRef, flattened as one big array
    my @valuesPlaceholders = ();
    my @allValues = ();
    foreach my $r (@$valuesRef) {
        push(@valuesPlaceholders, join(',', map { '?' } @$r));
        push(@allValues, @$r);
    }

    my $query = sprintf(
        "INSERT INTO %s (%s) VALUES (%s)",
        $tableName,
        join(',', @$columnNamesRef),
        join(',', @valuesPlaceholders)
    );

    try {
        my $sth = $self->dbh()->prepare($query);
        $sth->execute(@allValues);
    } catch {
        NeuroDB::DatabaseException->throw(
            statement    => $query,
            args         => [ @allValues ],
            errorCode    => $DBI::err,
            errorMessage => $DBI::errstr
        );
    }
}

=pod

=head3 C<disconnect()>

Terminates the connection previously instantiated to the database if a 
connection was previously established.

=cut

sub disconnect {
	my $self = shift;
	
        if($self->dbh) {
	    try {
	        $self->dbh->disconnect();
	    } catch {
	   	NeuroDB::DatabaseException->throw(
                    statement    => 'Call to disconnect failed',
                    args         => [],
                    errorCode    => $DBI::err,
                    errorMessage => $DBI::errstr
                );
            }
	}
}

=pod

=head3 C<DESTROY()>

Object destructor: terminates the connection previously instantiated to the
database (if any).

=cut
sub DESTROY {
	my $self = shift;
	
	$self->disconnect();
}

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

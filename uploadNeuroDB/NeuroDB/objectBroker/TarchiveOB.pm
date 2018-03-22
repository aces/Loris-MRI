package NeuroDB::objectBroker::TarchiveOB;

=pod

=head1 NAME

NeuroDB::objectBroker::TarchiveOB -- An object broker for tarchive records

=head1 SYNOPSIS

  use NeuroDB::Database;
  use NeuroDB::objectBroker::TarchiveOB;
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

  my $tarchiveOB = NeuroDB::objectBroker::TarchiveOB->new(db => $db);
  my $tarchivesRef;
  try {
      $tarchivesRef = $tarchiveOB->getByTarchiveLocation(
          [ 'TarchiveID' ], '/tmp/my_tarchive.tar.gz', 1
      );
  } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
      die sprintf(
          "Failed to retrieve tarchive records: %s",
          $e->errorMessage
      );
  }

=head1 DESCRIPTION

This class provides a set of methods to either fetch records from the C<tarchive>
table, insert new entries in it or update existing ones. If an operation cannot
be executed successfully, a C<NeuroDB::objectBroker::ObjectBrokerException> is thrown.

=head2 Methods

=cut

use Moose;
use MooseX::Privacy;

use NeuroDB::Database;
use NeuroDB::DatabaseException;
use NeuroDB::objectBroker::ObjectBrokerException;

use File::Basename;

use TryCatch;

my @TARCHIVE_FIELDS = qw(TarchiveID ArchiveLocation);

=pod

=head3 new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
C<Database> object used to access the database.

INPUT: the database object used to read/modify the C<tarchive> table.

RETURN: new instance of this class.

=cut

has 'db' => (is  => 'rw', isa => 'NeuroDB::Database', required => 1);

=pod

=head3 getByTarchiveLocation($fieldsRef, $tarchiveLocation, $baseNameMatch)

Fetches the records from the C<tarchive> table that have a specific archive location.

INPUTS:
    - reference to an array of the column names to return for each record found.
      Each element of this array must exist in C<@TARCHIVE_FIELDS> or an exception
      will be thrown.
    - path of the archive used during the search
    - boolean indicating if an exact match is sought (false) or if only basenames
      should be used when comparing two archive locations (true)

RETURN: a reference to an array of array references. This "matrix" contains the
        values of each colum for each record.

=cut

sub getByTarchiveLocation {
    my($self, $fieldsRef, $tarchiveLocation, $baseNameMatch) = @_;

    foreach my $f (@$fieldsRef) {
        if(!grep($f eq $_, @TARCHIVE_FIELDS)) {
            NeuroDB::objectBroker::ObjectBrokerException->throw(
                errorMessage => "Failed to retrieve tarchive record: invalid tarchive field $f"
            );
        }
    }

    my $query = sprintf(
        "SELECT %s FROM tarchive WHERE ArchiveLocation %s",
        join(',', (@$fieldsRef ? @$fieldsRef : @TARCHIVE_FIELDS)),
        $baseNameMatch ? 'LIKE ?' : '=?'
    );

    try {
        return $self->db->pselect(
            $query,
            $baseNameMatch ? ('%' . basename($tarchiveLocation) . '%') : $tarchiveLocation
        );
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to get tarchive records by tarchive location. Reason:\n%s",
                $e
            )
        );
    }
}

1;

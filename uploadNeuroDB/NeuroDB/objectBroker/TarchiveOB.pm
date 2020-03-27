package NeuroDB::objectBroker::TarchiveOB;

=pod

=head1 NAME

NeuroDB::objectBroker::TarchiveOB -- An object broker for C<tarchive> records

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
          [ 'TarchiveID' ], '/tmp/my_tarchive.tar.gz'
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

my @TARCHIVE_FIELDS = qw(
    TarchiveID ArchiveLocation PatientName PatientID PatientDoB md5sumArchive
    ScannerManufacturer ScannerModel ScannerSerialNumber ScannerSoftwareVersion
    neurodbCenterName SourceLocation
);

=pod

=head3 new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
C<Database> object used to access the database.

INPUT: the database object used to read/modify the C<tarchive> table.

RETURN: new instance of this class.

=cut

has 'db' => (is  => 'rw', isa => 'NeuroDB::Database', required => 1);

=pod

=head3 getByTarchiveLocation($tarchiveLocation)

Fetches the records from the C<tarchive> table that have a specific archive location.

INPUTS:
    - path of the archive used during the search.

RETURN: a reference to an array of hash references. Every hash contains the values for a given 
        row returned by the function call: the key/value pairs contain the name of a column 
        (listed in C<@TARCHIVE_FIELDS>) and the value it holds, respectively.
        As an example, suppose array C<$r> contains the result of a call to this method with 
        C<@$fieldsRef> set to C<('TarchiveID', 'SourceLocation'> one would fetch the C<TarchiveID> 
        of the 4th record returned using C<$r->[3]->{'TarchiveID'}>.
=cut

sub getByTarchiveLocation {
    my($self, $tarchiveLocation) = @_;

    # CONCAT ensures that ArchiveLocation always contains a slash at the beginning
    my $query = sprintf(
        "SELECT %s FROM tarchive WHERE CONCAT('/', ArchiveLocation) LIKE ? ",
        join(',', @TARCHIVE_FIELDS),
    );

    try {
        return $self->db->pselect(
            $query,
            ('%/' . quotemeta(basename($tarchiveLocation)))
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

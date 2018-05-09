package NeuroDB::objectBroker::MriScanTypeOB;

=pod

=head1 NAME

NeuroDB::objectBroker::MriScanTypeOB -- An object broker for mri_scan_type records

=head1 SYNOPSIS

  use NeuroDB::Database;
  use NeuroDB::objectBroker::MriScanTypeOB;
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

  my $mriScanTypeOB = NeuroDB::objectBroker::MriScanTypeOB->new(db => $db);
  my $mriScanTypeRef;
  try {
      $mriScanTypeRef = $mriScanTypeOB->get(
          0, { ScanType => 'dti' }
      );
  } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
      die sprintf(
          "Failed to retrieve tarchive records: %s",
          $e->errorMessage
      );
  }

=head1 DESCRIPTION

This class provides a set of methods to fetch records from the C<mri_scan_type>
table. If an operation cannot be executed successfully, a C<NeuroDB::objectBroker::ObjectBrokerException>
will be thrown.

=head2 Methods

=cut

use Moose;
use MooseX::Privacy;

use NeuroDB::Database;
use NeuroDB::DatabaseException;
use NeuroDB::objectBroker::ObjectBrokerException;

use TryCatch;

my @MRI_SCAN_TYPE_FIELDS = qw(ID Scan_type);

=pod

=head3 new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
C<Database> object used to access the database.

INPUT: the database object used to query the C<mri_scan_type> table.

RETURN: new instance of this class.

=cut

has 'db' => (is  => 'rw', isa => 'NeuroDB::Database', required => 1);

=pod
=head3 get($isCount, $columnValuesRef))
Fetches the entries in the C<mri_upload> table that have specific column
values. This method throws a C<NeuroDB::objectBroker::ObjectBrokerException>
if the operation could not be completed successfully.
INPUTS:
    - boolean indicating if only a count of the records found is needed
      or the full record properties.
    - reference to a hash array that contains the column values that the MRI records
      should have in order to be part of the result set (key: column name, value: column
      value).
      
RETURNS: either a count of the records found or a reference to an array of hashes, each 
         hash being an MRI record found, with all the columns set to whatever was found
         in the database.
=cut

sub get {
	my($self, $isCount, $columnValuesRef) = @_;

    my @where;
    
    if (%$columnValuesRef) {
        foreach my $k (keys %$columnValuesRef) {
            if(!grep($k eq $_, @MRI_SCAN_TYPE_FIELDS)) {
                NeuroDB::objectBroker::ObjectBrokerException->throw(
                    errorMessage => "MRI scan type get failed: invalid MRI scan type field $k"
                );
            }
            push(@where, "$k=?");
        }
	}

    my $select = $isCount ? 'COUNT(*)' : '*';

    my $query = "SELECT $select FROM mri_scan_type";
    $query .= sprintf(' WHERE %s', join(' AND ', @where)) if @where;

    try {
        return $self->db->pselect($query, values(%$columnValuesRef));
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to retrieve MRI scan type records. Reason:\n%s",
                $e
            )
        );
    }
}

1;

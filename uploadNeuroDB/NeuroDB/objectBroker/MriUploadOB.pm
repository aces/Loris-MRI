package NeuroDB::objectBroker::MriUploadOB;

=pod

=head1 NAME

NeuroDB::objectBroker::MriUploadOB -- An object broker for MRI uploads

=head1 SYNOPSIS

  use NeuroDB::Database;
  use NeuroDB::objectBroker::MriUploadOB;
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

  my $mriUploadOB = NeuroDB::objectBroker::MriUploadOB->new(db => $db);
  my $mriUploadsRef;
  try {
      $mriUploadsRef= $mriUploadOB->getWithTarchive(1, '/tmp/my_tarchive.tar.gz');
  } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
      die sprintf(
          "Failed to retrieve MRI uploads: %s",
          $e->errorMessage
      );
  }

=head1 DESCRIPTION

This class provides a set of methods to either fetch or insert MRI upload
records. The operations are always performed on database table C<mri_upload>.
Each method will throw a C<NeuroDB::objectBroker::ObjectBrokerException> if 
the request could not be performed successfully.

=head2 Methods

=cut

use Moose;
use MooseX::Privacy;

use File::Basename;

use NeuroDB::Database;
use NeuroDB::DatabaseException;
use NeuroDB::objectBroker::ObjectBrokerException;

use TryCatch;

# These are the only fields modified when inserting a new MRI upload record
my @MRI_UPLOAD_FIELDS = (
    'UploadedBy' ,'UploadDate','TarchiveID','DecompressedLocation', 'UploadLocation', 'PatientName',
    'IsTarchiveValidated', 'UploadID'
);

=pod

=head3 new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
C<Database> object used to access the database.

INPUT: the database object used to read/modify the C<mri_upload> table.

RETURNS: new instance of this class.

=cut

has 'db'     => (is  => 'rw', isa => 'NeuroDB::Database', required => 1);

=pod

=head3 getWithTarchive($isCount, $tarchiveLocation)

Fetches the entries in the C<mri_upload> table that have a specific archive
location. This method throws a C<NeuroDB::objectBroker::ObjectBrokerException>
if the operation could not be completed successfully.

INPUTS:
    - boolean indicating if only a count of the records found is needed
      or the full record properties.
    - path of the archive location.

RETURNS: a reference to an array of array references. If C<$isCount> is true, then
         C<< $returnValue->[0]->[0] >> will contain the count of records sought. Otherwise
         C<< $returnValue->[x]->[y] >> will contain the value of the yth column (in array
         C<@MRI_UPLOAD_FIELDS> for the xth record retrieved.
=cut

sub getWithTarchive {
    my($self, $isCount, $tarchiveLocation) = @_;

    # We must preceed all the MRI upload fields with the table name they are issued from
    # to avoid clashes with fields in table tarchive when building the SQL statement later on  
    my $select = $isCount ? 'COUNT(*)' : join(',', (map { "mri_upload.$_" } @MRI_UPLOAD_FIELDS));

    # CONCAT ensures that ArchiveLocation always contains a slash at the beginning
    my $query = "SELECT $select "
        .       "FROM mri_upload "
        .       "JOIN tarchive USING(TarchiveID) "
        .       "WHERE CONCAT('/', ArchiveLocation) LIKE ? ";

    try {
        return $self->db->pselect(
            $query,
            ('%/' . quotemeta(basename($tarchiveLocation)))
        );
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to retrieve mri upload records. Reason:\n%s",
                $e
            )
        );
    }
}

=pod

=head3 getWithUploadID($isCount, $uploadID)($isCount, $uploadID)

Fetches the entries in the C<mri_upload> table based on an UploadID.
This method throws a C<NeuroDB::objectBroker::ObjectBrokerException>
if the operation could not be completed successfully.

INPUTS:
    - boolean indicating if only a count of the records found is needed
      or the full record properties.
    - path of the archive location.

RETURNS: a reference to an array of array references. If C<$isCount> is true, then
         C<< $returnValue->[0]->[0] >> will contain the count of records sought. Otherwise
         C<< $returnValue->[x]->[y] >> will contain the value of the yth column (in array
         C<@MRI_UPLOAD_FIELDS> for the xth record retrieved.
=cut

sub getWithUploadID {
    my($self, $uploadID, $isCount) = @_;

    # We must preceed all the MRI upload fields with the table name they are issued from
    # to avoid clashes with fields in table tarchive when building the SQL statement later on
    my $select = $isCount ? 'COUNT(*)' : join(',', (map { "mri_upload.$_" } @MRI_UPLOAD_FIELDS));

    try {
        return $self->db->pselect(
            "SELECT $select FROM mri_upload WHERE UploadID = ? ",
            $uploadID
        );
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to retrieve mri upload records. Reason:\n%s",
                $e
            )
        );
    }
}

=pod

=head3 insert($valuesRef)

Inserts a new record in the C<mri_upload> table with the specified column values.
This method throws a C<NeuroDB::objectBroker::ObjectBrokerException> if the operation
could not be completed successfully.

INPUT: a reference to a hash of the values to insert. The hash contains the column
       names and associated record values used during insertion. All the keys of
       C<%$valuesRef> must exist in C<@MRI_UPLOAD_FIELDS> or an exception will be thrown.

RETURNS: the index of the MRI upload record inserted.

=cut

sub insert {
    my($self, $valuesRef) = @_;

    if(!keys %$valuesRef) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => "MRI upload insertion failed: no values specified"
        );
    }

    foreach my $v (keys %$valuesRef) {
        if(!grep($v eq $_, @MRI_UPLOAD_FIELDS)) {
            NeuroDB::objectBroker::ObjectBrokerException->throw(
                errorMessage => "MRI upload insertion failed: invalid MRI upload field $v"
            );
        }
    }

    try {
        my @results = $self->db->insertOne('mri_upload', $valuesRef);
        return $results[0];
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to insert mri_upload record. Reason:\n%s",
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

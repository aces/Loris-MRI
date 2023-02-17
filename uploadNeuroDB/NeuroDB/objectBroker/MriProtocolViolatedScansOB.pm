package NeuroDB::objectBroker::MriProtocolViolatedScansOB;

=pod

=head1 NAME

NeuroDB::objectBroker::MriProtocolViolatedScansOB -- An object broker for C<mri_protocol_violated_scans> records

=head1 SYNOPSIS

  use NeuroDB::Database;
  use NeuroDB::objectBroker::MriProtocolViolatedScansOB;
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

  my $mriProtocolViolatedScansOB = NeuroDB::objectBroker::MriProtocolViolatedScansOB->new(db => $db);
  my $mriProtocolViolatedScansOBRef;
  try {
      $mriProtocolViolatedScansOBRef = $mriProtocolViolatedScansOB->getByTarchiveID(
          [ 'TarchiveID' ], 12
      );
  } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
      die sprintf(
          "Failed to retrieve mri_protocol_violated_scans records: %s",
          $e->errorMessage
      );
  }

=head1 DESCRIPTION

This class provides a set of methods to either fetch records from the C<mri_protocol_violated_scans>
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

my @MRIPROTOCOLVIOLATEDSCANS_FIELDS = qw(
    ID CandID PSCID TarchiveID time_run series_description minc_location
    PatientName TR_range TE_range TI_range slice_thickness_range
    xspace_range yspace_range zspace_range xstep_range ystep_range zstep_range
    time_range SeriesUID image_type PhaseEncodingDirection EchoNumber
    MriProtocolGroupID
);

=pod

=head3 new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
C<Database> object used to access the database.

INPUT: the database object used to read/modify the C<mri_protocol_violated_scans> table.

RETURN: new instance of this class.

=cut

has 'db' => (is  => 'rw', isa => 'NeuroDB::Database', required => 1);

=pod

=head3 getWithTarchiveID($tarchiveID)

Fetches the records from the C<mri_protocol_violated_scans> table that have a specific C<TarchiveID>.

INPUTS:
    - ID of the tarchive used during the search.

RETURN: a reference to an array of hash references. Every hash contains the values for a given
        row returned by the function call: the key/value pairs contain the name of a column
        (listed in C<@MRIPROTOCOLVIOLATEDSCANS_FIELDS>) and the value it holds, respectively.
        As an example, suppose array C<$r> contains the result of a call to this method with
        C<@$fieldsRef> set to C<('TarchiveID', 'minc_location'> one would fetch the C<minc_location>
        of the 4th record returned using C<$r->[3]->{'minc_location'}>.
=cut

sub getWithTarchiveID {
    my ($self, $tarchiveID) = @_;

    my $query = sprintf(
        "SELECT %s FROM mri_protocol_violated_scans WHERE TarchiveID = ? ",
        join(',', @MRIPROTOCOLVIOLATEDSCANS_FIELDS)
    );

    try {
        return $self->db->pselect(
            $query, $tarchiveID
        );
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to get mri_protocol_violated_scans records by tarchive ID. Reason:\n%s",
                $e
            )
        );
    }
}

=head3 insert($valuesRef)

Inserts a new record in the C<mri_protocol_violated_scans> table with the specified column values.
This method throws a C<NeuroDB::objectBroker::ObjectBrokerException> if the operation
could not be completed successfully.

INPUT: a reference to a hash of the values to insert. The hash contains the column
       names and associated record values used during insertion. All the keys of
       C<%$valuesRef> must exist in C<@MRIPROTOCOLVIOLATEDSCANS_FIELDS> or an exception will be thrown.

RETURNS: the index of the MRI upload record inserted.

=cut

sub insert {
    my($self, $valuesRef) = @_;

    if(!keys %$valuesRef) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => "MRI protocol violated scans insertion failed: no values specified"
        );
    }

    foreach my $v (keys %$valuesRef) {
        if(!grep($v eq $_, @MRIPROTOCOLVIOLATEDSCANS_FIELDS)) {
            NeuroDB::objectBroker::ObjectBrokerException->throw(
                errorMessage => "MRI protocol violated scans insertion failed: invalid field $v"
            );
        }
    }

    try {
        print($valuesRef);
        my @results = $self->db->insertOne('mri_protocol_violated_scans', $valuesRef);
        return $results[0];
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf(
                "Failed to insert mri_protocol_violated_scans record. Reason:\n%s",
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
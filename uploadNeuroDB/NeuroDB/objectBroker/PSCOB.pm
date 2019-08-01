package NeuroDB::objectBroker::PSCOB;

=pod

=head1 NAME

NeuroDB::objectBroker::PSCOB -- An object broker for records stored in table C<psc>.

=head1 SYNOPSIS

  use NeuroDB::Database;
  use NeuroDB::DatabaseException;
  use NeuroDB::objectBroker::PSCOB;
  use NeuroDB::objectBroker::ObjectBrokerException;
  
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

  my $pscOB = NeuroDB::objectBroker::PSCOB->new(db => $db);
  my $pscRef;
  try {
      $pscRef = $pscOB->get(
          { MRI_alias => 'my_alias' }
      );
      foreach (@$pscRef) {
          printf "ID for PSC named $_->{'Name'} is $_->{'ID'}\n";
      }

      # Fetch the PSC with a NULL Alias
      $pscRef = $pscOB->get(
          { Alias => undef }
      );
      
      # Fetch all PSCs except the DCC
      $pscRef = $pscOB->get(
          { Name => { NOT => 'Data Coordinating Center' } }
      );
  } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
      die sprintf(
          "Failed to retrieve psc records: %s",
          $e->errorMessage
      );
  }

=head1 DESCRIPTION

This class provides a set of methods to fetch records from the C<psc>
table. If an operation cannot be executed successfully, a C<NeuroDB::objectBroker::ObjectBrokerException>
will be thrown. See the documentation for C<GetRole> for information on how to perform
basic C<SELECT> operations using this object broker.

=head2 Methods

=cut

use Moose;

extends 'NeuroDB::objectBroker::ObjectBroker';

with 'NeuroDB::objectBroker::GetRole';

use TryCatch;

my $TABLE_NAME = "psc";

my @COLUMN_NAMES = qw(CenterID Name Alias MRI_alias);

=pod

=head3 getTableName()

Gets the name of the database table with which this object broker interacts.

INPUT: None

RETURN: name of the database table with which this object broker interacts.

=cut


sub getTableName {
	return $TABLE_NAME;
}

=pod 

=head3 getColumnNames()

Gets the column names for table psc.

INPUT: None

RETURN: Column names for table psc.

=cut
sub getColumnNames {
	return @COLUMN_NAMES;
}

1;

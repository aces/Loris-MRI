package NeuroDB::objectBroker::MriScannerOB;

=pod

=head1 NAME

NeuroDB::objectBroker::MriScannerOB -- An object broker for mri_scanner records

=head1 SYNOPSIS

  use NeuroDB::Database;
  use NeuroDB::objectBroker::MriScannerOB;
  use NeuroDB::DatabaseException;
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

  my $mriScannerOB = NeuroDB::objectBroker::MriScannerOB->new(db => $db);
  my $mriScannerRef;
  try {
      $mriScannerRef = $mriScannerOB->get(
          { Software => 'my_software' }
      );
      foreach(@$mriScannerRef) {
          print "ID for scanner model $_->{'Model'} is $_->{'ID'}\n";
      }
      
      # Fetch the scanner with a NULL manufacturer
      $mriScannerRef = $mriScannerOB->get(
          { Manufacturer => undef }
      );
      
      # Fetch the scanners with a CandID != 999999
      $mriScannerRef = $mriScannerOB->get(
          { CandID => { NOT => 999999 } }
      );
      
      # Create a new scanner with the given properties
      mriScannerOB->insertOne({
          ID            => 7,
          Manufacturer  => 'SIEMENS',
          Model         => 'Prisma_fit',
          Serial_number => 67094,
          Software      => 'syngo MR E11',
          CandID        => 151581
      });
  } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
      die sprintf(
          "Failed to retrieve mri_scanner records: %s",
          $e->errorMessage
      );
  }

=head1 DESCRIPTION

This class provides a set of methods to fetch records from the C<mri_scanner>
table. If an operation cannot be executed successfully, a C<NeuroDB::objectBroker::ObjectBrokerException>
will be thrown. See the documentation for C<GetRole> and C<InsertRole> for information on how to perform
basic C<INSERT>/C<SELECT> operations using this object broker.

=cut

use Moose;

extends 'NeuroDB::objectBroker::ObjectBroker';

with 'NeuroDB::objectBroker::GetRole';
with 'NeuroDB::objectBroker::InsertRole';

use TryCatch;

my $TABLE_NAME = "mri_scanner";

my @COLUMN_NAMES = qw(ID Manufacturer Model Serial_number Software CandID);

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

Gets the column names for table mri_scanner.

INPUT: None

RETURN: Column names for table mri_scanner.

=cut

sub getColumnNames {
	return @COLUMN_NAMES;
}

1;

package NeuroDB::objectBroker::ConfigOB;

=pod

=head1 NAME

NeuroDB::objectBroker::ConfigOB -- An object broker for configuration settings

=head1 SYNOPSIS

  use NeuroDB::Database;
  use NeuroDB::objectBroker::ConfigOB;
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

  my $configOB = NeuroDB::objectBroker::ConfigOB(db => $db);
  my $tarchiveLibraryPath;
  try {
      $tarchiveLibraryPath = $configOB->getTarchiveLibraryPath();
  } catch(NeuroDB::objectBroker::ObjectBrokerException $e) {
      die sprintf(
          "Failed to retrieve tarchive library path: %s",
          $e->errorMessage
      );
  }

=head1 DESCRIPTION

This class provides a set of methods to fetch specific configuration settings
from the C<Config> LORIS database.

=head2 Methods

=cut

use Moose;
use MooseX::Privacy;

use NeuroDB::Database;
use NeuroDB::DatabaseException;
use NeuroDB::objectBroker::ObjectBrokerException;

use TryCatch;

use constant TARCHIVE_LIBRARY_DIR => 'tarchiveLibraryDir';

=pod

=head3 new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
C<Database> object used to access the database.

INPUT: the database object used to fetch the settings.

RETURN: new instance of this class.

=cut

has 'db'     => (is  => 'rw', isa => 'NeuroDB::Database', required => 1);


=head3 &$getConfigSettingRef($setting)

Private method. This method fetches setting C<$setting> from the LORIS table 
Config. It will throw a C<NeuroDB::objectBroker::ObjectBrokerException> if either
the database transaction failed for some reason or it succeeded but returned no
results (i.e. setting $setting does not exist).

INPUT: name of the setting to fetch.

RETURN: the setting value (as a string). If the setting value is NULL, then this
         method will return C<undef>.

=cut

my $getConfigSettingRef = sub {
    my($self, $setting) = @_;

    my $result;
    try {
        $result = $self->db->pselect(
            'SELECT c.value FROM Config c '
                . 'JOIN ConfigSettings cs ON (cs.ID=c.ConfigID) '
                . 'WHERE cs.Name = ?',
            $setting
        );
    } catch(NeuroDB::DatabaseException $e) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => sprintf("Failed to get config setting '%s': %s",
                                    $setting, $e)
        );
    }

    if(@$result == 0) {
        NeuroDB::objectBroker::ObjectBrokerException->throw(
            errorMessage => "Setting '$setting' does not exist in database table Config"
        );
    }

    return $result->[0]->{'value'};
};

=head3 getTarchiveLibraryDir()

Gets the tarchive library dir.

RETURN: value (string) of the tarchive library dir in the Config table.

=cut

sub getTarchiveLibraryDir {
    my $self = shift;

    return &$getConfigSettingRef($self, TARCHIVE_LIBRARY_DIR);
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

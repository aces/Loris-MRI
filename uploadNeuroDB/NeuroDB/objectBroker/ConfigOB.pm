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

use constant TARCHIVE_LIBRARY_DIR      => 'tarchiveLibraryDir';
use constant DATA_DIR_BASE_PATH        => 'dataDirBasepath';
use constant MAIL_USER                 => 'mail_user';
use constant MRI_CODE_PATH             => 'MRICodePath';
use constant PREFIX                    => 'prefix';
use constant DTI_VOLUMES               => 'DTI_volumes';
use constant T1_SCAN_TYPE              => 't1_scan_type';
use constant REJECT_THRESHOLD          => 'reject_thresh';
use constant NIAK_PATH                 => 'niak_path';
use constant QCED2_STEP                => 'QCed2_step';
use constant GET_DICOM_INFO            => 'get_dicom_info';
use constant CONVERTER                 => 'converter';
use constant LOOK_UP_CENTER_NAME_USING => 'lookupCenterNameUsing';
use constant DEFACING_REF_SCAN_TYPE    => 'reference_scan_type_for_defacing';
use constant LEGO_PHANTOM_REGEX        => 'LegoPhantomRegex';
use constant LIVING_PHANTOM_REGEX      => 'LivingPhantomRegex';
use constant CREATE_NII                => 'create_nii';
use constant HORIZONTAL_PICS           => 'horizontalPics';
use constant IS_QSUB                   => 'is_qsub';
use constant CREATE_CANDIDATES         => 'createCandidates';
use constant USE_PROJECTS              => 'useProjects';

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


=head3 &$getBooleanRef($value)

Private method. This method returns 1 if a boolean value is set to either 'true'
or '1'; 0 otherwise. This ensures harmonization of the boolean settings.

INPUT: boolean value extracted from the Config table

RETURN: 1 if the value provided is 'true' or '1'; 0 otherwise

=cut
my $getBooleanRef = sub {
    my ($value) = @_;

    return ($value eq "true" || $value == 1) ? 1 : 0;
};

=head3 getTarchiveLibraryDir()

Gets the tarchive library dir.

RETURN: value (string) of the tarchive library dir in the Config table.

=cut

sub getTarchiveLibraryDir {
    my $self = shift;

    my $path = &$getConfigSettingRef($self, TARCHIVE_LIBRARY_DIR);
    $path    =~ s!/$!!;

    return $path;
}

=head3 getDataDirPath()

Get the data directory path.

RETURN: value (sting) of the data directory path in the Config table.

=cut
sub getDataDirPath {
    my $self = shift;

    my $path = &$getConfigSettingRef($self, DATA_DIR_BASE_PATH);
    $path    =~ s!/$!!;

    return $path;
}

=head3 getMriCodePath()

Get the MRI code path.

RETURN: value (string) of the MRI code path in the Config table.

=cut
sub getMriCodePath {
    my $self = shift;

    my $path = &$getConfigSettingRef($self, MRI_CODE_PATH);
    $path    =~ s!/$!!;

    return $path;
}

=head3 getNiakPath()

Get the NIAK package path.

RETURN: value (string) of the NIAK package path in the Config table.

=cut
sub getNiakPath {
    my $self = shift;

    my $path = &$getConfigSettingRef($self, NIAK_PATH);
    $path    =~ s!/$!!;

    return $path;
}

=head3 getMailUser()

Get the mail user.

RETURN: value (string) of the mail user in the Config table.

=cut
sub getMailUser {
    my $self = shift;

    return &$getConfigSettingRef($self, MAIL_USER);
}


=head3 getPrefix()

Get the study prefix.

RETURN: value (string) of the study prefix in the Config table.

=cut
sub getPrefix {
    my $self = shift;

    return &$getConfigSettingRef($self, PREFIX);
}

=head3 getDtiVolumes()

Get the number of DTI volumes.

RETURN: value (string) of the number of DTI volumes in the Config table.

=cut
sub getDtiVolumes {
    my $self = shift;

    return &$getConfigSettingRef($self, DTI_VOLUMES);
}

=head3 getT1ScanType()

Get the T1 scan type.

RETURN: value (string) of the T1 scan type in the Config table.

=cut
sub getT1ScanType {
    my $self = shift;

    return &$getConfigSettingRef($self, T1_SCAN_TYPE);
}

=head3 getQced2Step()

Get the QCed2 step dataset name.

RETURN: value (string) of the QCed2 step dataset name in the Config table.

=cut
sub getQced2Step {
    my $self = shift;

    return &$getConfigSettingRef($self, QCED2_STEP);
}

=head3 getDicomInfo()

Get the get_dicom_info.pl path.

RETURN: value (string) of the get_dicom_info.pl path in the Config table.

=cut
sub getDicomInfo {
    my $self = shift;

    return &$getConfigSettingRef($self, GET_DICOM_INFO);
}

=head3 getConverter()

Get the converter name.

RETURN: value (string) of the converter name in the Config table.

=cut
sub getConverter {
    my $self = shift;

    return &$getConfigSettingRef($self, CONVERTER);
}

=head3 getLookupCenterNameUsing()

Get the lookup center name using.

RETURN: value (string) of the lookup center name using in the Config table.

=cut
sub getLookupCenterNameUsing {
    my $self = shift;

    return &$getConfigSettingRef($self, LOOK_UP_CENTER_NAME_USING);
}

=head3 getDefacingRefScanType()

Get the defacing reference scan type.

RETURN: value (string) of the defacing reference scan type in the Config table.

=cut
sub getDefacingRefScanType {
    my $self = shift;

    return &$getConfigSettingRef($self, DEFACING_REF_SCAN_TYPE);
}

=head3 getLegoPhantomRegex()

Get the lego phantom regular expression.

RETURN: value (string) of the lego phantom regular expression in the Config table.

=cut
sub getLegoPhantomRegex {
    my $self = shift;

    return &$getConfigSettingRef($self, LEGO_PHANTOM_REGEX);
}

=head3 getLivingPhantomRegex()

Get the living phantom regular expression.

RETURN: value (string) of the living phantom regular expression in the Config table.

=cut
sub getLivingPhantomRegex {
    my $self = shift;

    return &$getConfigSettingRef($self, LIVING_PHANTOM_REGEX);
}

=head3 getCreateNii()

Get the create_nii Config setting.

RETURN: (boolean) 1 if create_nii is set to Yes in the Config module, 0 otherwise

=cut
sub getCreateNii {
    my $self = shift;

    my $value = &$getConfigSettingRef($self, CREATE_NII);

    return $getBooleanRef->($value);
}

=head3 getHorizontalPics()

Get the horizontalPics Config setting.

RETURN: (boolean) 1 if horizontalPics is set to Yes in the Config module, 0 otherwise

=cut
sub getHorizontalPics {
    my $self = shift;

    my $value = &$getConfigSettingRef($self, HORIZONTAL_PICS);

    return $getBooleanRef->($value);
}

=head3 getIsQsub()

Get the is_qsub Config setting.

RETURN: (boolean) 1 if is_qsub is set to Yes in the Config module, 0 otherwise

=cut
sub getIsQsub {
    my $self = shift;

    my $value = &$getConfigSettingRef($self, IS_QSUB);

    return $getBooleanRef->($value);
}

=head3 getUseProjects()

Get the useProjects Config setting.

RETURN: (boolean) 1 if useProjects is set to Yes in the Config module, 0 otherwise

=cut
sub getUseProjects {
    my $self = shift;

    my $value = &$getConfigSettingRef($self, USE_PROJECTS);

    return $getBooleanRef->($value);
}

=head3 getCreateCandidates()

Get the createCandidates Config setting.

RETURN: (boolean) 1 if createCandidates is set to Yes in the Config module, 0 otherwise

=cut
sub getCreateCandidates {
    my $self = shift;

    my $value = &$getConfigSettingRef($self, CREATE_CANDIDATES);

    return $getBooleanRef->($value);
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

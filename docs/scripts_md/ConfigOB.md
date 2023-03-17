# NAME

NeuroDB::objectBroker::ConfigOB -- An object broker for configuration settings

# SYNOPSIS

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

# DESCRIPTION

This class provides a set of methods to fetch specific configuration settings
from the `Config` LORIS database.

## Methods

### new(db => $db) >> (constructor)

Create a new instance of this class. The only parameter to provide is the
`Database` object used to access the database.

INPUT: the database object used to fetch the settings.

RETURN: new instance of this class.

### &$getConfigSettingRef($setting)

Private method. This method fetches setting `$setting` from the LORIS table 
Config. It will throw a `NeuroDB::objectBroker::ObjectBrokerException` if either
the database transaction failed for some reason or it succeeded but returned no
results (i.e. setting `$setting` does not exist).

INPUT: name of the setting to fetch.

RETURN: the setting value. If the setting is does not allow for multiple values, then this method
        will return a string (unless the setting value is NULL, in which case this method returns `undef`).
        Otherwise, this method returns an array, possibly empty.

### &$getBooleanRef($value)

Private method. This method returns 1 if a boolean value is set to either 'true'
or '1'; 0 otherwise. This ensures harmonization of the boolean settings.

INPUT: boolean value extracted from the Config table

RETURN: 1 if the value provided is 'true' or '1'; 0 otherwise

### getTarchiveLibraryDir()

Gets the tarchive library dir.

RETURN: value (string) of the tarchive library dir in the Config table.

### getDataDirPath()

Get the data directory path.

RETURN: value (sting) of the data directory path in the Config table.

### getMriCodePath()

Get the MRI code path.

RETURN: value (string) of the MRI code path in the Config table.

### getNiakPath()

Get the NIAK package path.

RETURN: value (string) of the NIAK package path in the Config table.

### getMailUser()

Get the mail user.

RETURN: value (string) of the mail user in the Config table.

### getPrefix()

Get the study prefix.

RETURN: value (string) of the study prefix in the Config table.

### getDtiVolumes()

Get the number of DTI volumes.

RETURN: value (string) of the number of DTI volumes in the Config table.

### getT1ScanType()

Get the T1 scan type.

RETURN: value (string) of the T1 scan type in the Config table.

### getQced2Step()

Get the QCed2 step dataset name.

RETURN: value (string) of the QCed2 step dataset name in the Config table.

### getDicomInfo()

Get the get\_dicom\_info.pl path.

RETURN: value (string) of the get\_dicom\_info.pl path in the Config table.

### getConverter()

Get the converter name.

RETURN: value (string) of the converter name in the Config table.

### getLookupCenterNameUsing()

Get the lookup center name using.

RETURN: value (string) of the lookup center name using in the Config table.

### getDefacingRefScanType()

Get the defacing reference scan type.

RETURN: value (string) of the defacing reference scan type in the Config table.

### getLegoPhantomRegex()

Get the lego phantom regular expression.

RETURN: value (string) of the lego phantom regular expression in the Config table.

### getLivingPhantomRegex()

Get the living phantom regular expression.

RETURN: value (string) of the living phantom regular expression in the Config table.

### getCreateNii()

Get the create\_nii Config setting.

RETURN: (boolean) 1 if create\_nii is set to Yes in the Config module, 0 otherwise

### getHorizontalPics()

Get the horizontalPics Config setting.

RETURN: (boolean) 1 if horizontalPics is set to Yes in the Config module, 0 otherwise

### getIsQsub()

Get the is\_qsub Config setting.

RETURN: (boolean) 1 if is\_qsub is set to Yes in the Config module, 0 otherwise

### getCreateCandidates()

Get the createCandidates Config setting.

RETURN: (boolean) 1 if createCandidates is set to Yes in the Config module, 0 otherwise

### getCreateVisit()

Get the createVisit Config setting.

RETURN: (boolean) 1 if createVisit is set to Yes in the Config module, 0 otherwise

### getDefaultProject()

Get the default_project Config setting.

RETURN: value (string) of the default_project config in the Config table.

### getDefaultCohort()

Get the default_cohort Config setting.

RETURN: value (string) of the default_cohort config in the Config table.

### getPythonConfigFile()

Get the MriPythonConfigFile Config setting.

RETURN: value (string) of the MRI python config file in the Config table.

### getComputeSnrModalities()

Get the compute\_snr\_modalities Config setting

RETURN: an array (possibly empty) of the modality IDs (i.e t1w, etc..) for which to compute the SNR

### getExcludedSeriesDescription()

Get the excluded\_series\_description Config setting

RETURN: an array (possibly empty) of the series description to exclude from import

### getModalitiesToDeface()

Get the modalities\_to\_deface Config setting

RETURN: an array (possibly empty) of the modalities to run the defacing pipeline on

### getBidsDatasetAuthors()

Get the bids\_dataset\_authors Config setting

RETURN: an array (possibly empty) of the authors to use for a BIDS dataset

### getBidsAcknowledgmentsText()

Get the bids\_acknowledgments\_text Config setting

RETURN: a string of the acknowledgment text to use for a BIDS dataset (or undef)

### getBidsReadmeText()

Get the bids\_readme\_text Config setting

RETURN: a string of the README text to use for a BIDS dataset (or undef)

### getBidsValidatorOptionsToIgnore()

Get the bids\_validator\_options\_to\_ignore Config setting

RETURN: an array of the BIDS validator options to ignore
to use when creating a BIDS dataset

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

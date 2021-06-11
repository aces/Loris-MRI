#! /usr/bin/perl
=pod


=head1 NAME

MakeNIIFilesBIDSCompliant.pl -- a script that creates a BIDS compliant imaging
dataset from the MINC files present in the C<assembly/> directory


=head1 SYNOPSIS

perl tools/MakeNIIFilesBIDSCompliant.pl C<[options]>

Available options are:
-profile             : name of the config file in C<../dicom-archive/.loris_mri>
-tarchive_id         : The ID of the DICOM archive to be converted into a BIDS
                       dataset (optional, if not set, convert all DICOM archives)
-dataset_name        : Name/Description of the dataset to be generated in BIDS
                       format; for example BIDS_First_Sample_Data. The BIDS data
                       will be stored in a directory with that C<dataset_name>
                       under the C<BIDS_export> directory.
-slice_order_philips : Philips scanners do not have the C<SliceOrder> in their
                       DICOM headers so it needs to be provided an argument to
                       this script. C<ascending> or C<descending> are expected.
                       If slice order is C<interleaved>, then it needs to be logged
                       in the JSON as C<Not Supplied>
-verbose             : if set, be verbose


=head1 DESCRIPTION

This **BETA** version script will create a BIDS compliant NIfTI file structure of
the MINC files currently present in the C<assembly> directory. If the argument
C<tarchive_id> is specified, only the images from that archive will be processed.
Otherwise, all C<tarchive_id>'s present in the C<tarchive> table will be processed.

The script expects the tables C<bids_category> and C<bids_mri_scan_type_rel> to
be populated and customized as per the project's acquisition protocols. Keep the
following restrictions/expectations in mind when populating the two database tables.

C<bids_category> will house the different imaging "categories" which a default
install would set to C<anat>, C<func>, C<dwi>, and C<fmap>. More entries can be
added as more imaging categories are supported by the BIDS standards.

For the C<bids_mri_scan_type_rel> table, functional modalities such as
resting-state fMRI and task fMRI expect their C<BIDSScanTypeSubCategory> column be
filled as follows: a hyphen concatenated string, with the first part describing
the BIDS imaging sub-category, "task" as an example here, and the second
describing this sub-category, "rest" or "memory" as an example. Note that the
second part after the hyphen is used in the JSON file for the header "TaskName".
Multi-echo sequences would be expected to see their C<BIDSMultiEcho> column
filled with "echo-1", "echo-2", etc...
Filling out these values properly as outlined in this description is mandatory
as these values will be used to rename the NIfTI file, as per the BIDS
requirements.

Running this script requires JSON library for Perl.
Run C<sudo apt-get install libjson-perl> to get it.


=head2 METHODS

=cut


# TODO: BEFORE RUNNING THE SCRIPT, CONFIGURE TABLES ABOVE + MODIFY CONSTANTS IN THE
# TODO: SCRIPT WITH THE CONSTANTS BELOW (EXPLAIN WHAT THEY ARE)


# Imports
use strict;
use warnings;
use File::Path qw/ make_path /;
use File::Basename;
use Getopt::Tabular;
use JSON;
use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::ExitCodes;
use NeuroDB::File;


# Set script's constants here
my @AUTHORS = ['LORIS', 'MCIN', 'MNI', 'McGill University'];
my $ACKNOWLEDGMENTS = <<TEXT;
TEXT
my $README = <<TEXT;
This dataset was produced by LORIS-MRI scripts.
TEXT
my $BIDS_VALIDATOR_CONFIG = <<TEXT;
{
  "ignore": []
}
TEXT
my $LORIS_SCRIPT_VERSION = "0.2"; # Still a BETA version
my $BIDS_VERSION         = "1.1.1 & BEP0001";


# Create GetOpt
my $profile;
my $tarchive_id;
my $dataset_name;
my $verbose;
my $slice_order_philips = "Not Supplied";

my $profile_desc      = "Name of the config file in ../dicom-archive/.loris_mri (typically 'prod')";
my $tarchive_id_desc  = "TarchiveID from the tarchive table of the .tar archive to be processed.";
my $dataset_name_desc = "Name/Description of the BIDS dataset to be generated";
my $slice_order_desc  = "Slice order for Philips acquisition: 'ascending', 'descending' or 'Not Supplied'";

my @opt_table = (
    [ "-profile",             "string",  1, \$profile,             $profile_desc      ],
    [ "-tarchive_id",         "string",  1, \$tarchive_id,         $tarchive_id_desc  ],
    [ "-dataset_name",        "string",  1, \$dataset_name,        $dataset_name_desc ],
    [ "-slice_order_philips", "string",  1, \$slice_order_philips, $slice_order_desc  ],
    [ "-verbose",             "boolean", 1, \$verbose,             "Be verbose."      ]
);

# TODO MODIFY HELP TO BE LIKE THE DESCRIPTION ABOVE ONCE FINALIZED
my $Help = <<HELP;
This **BETA** version script will create a BIDS compliant NII file structure of
the MINC files currently present in the assembly directory. If the argument
tarchive_id is specified, only the images from that archive will be processed.
Otherwise, all files in assembly will be included in the BIDS structure,
while looping though all the tarchive_id's in the tarchive table.
The script expects the tables C<bids_category> and C<bids_mri_scan_type_rel> to
be populated and customized as per the project acquisitions. Keep the following
restrictions/expectations in mind when populating the two database tables.
C<bids_category> will house the different imaging "categories" which a default
install would set to C<anat>, C<func>, C<dwi>, and C<fmap>. More entries can be
added as more imaging categories are supported by the BIDS standards.
For the C<bids_mri_scan_type_rel> table, functional modalities such as
resting-state fMRI and task fMRI expect their BIDSScanTypeSubCategory column be
filled as follows: a hyphen concatenated string, with the first part describing
the BIDS imaging sub-category, "task" as an example here, and the second
describing this sub-category, "rest" or "memory" as an example. Note that the
second part after the hyphen is used in the JSON file for the header "TaskName".
Multi-echo sequences would be expected to see their C<BIDSMultiEcho> column
filled with "echo-1", "echo-2", etc...
Filling out these values properly as outlined in this description is mandatory
as these values will be used to rename the NIfTI file, as per the BIDS
requirements.
Running this script requires JSON library for Perl.
Run sudo apt-get install libjson-perl to get it.
Documentation: perldoc tools/MakeNIIFilesBIDSCompliant.pl
HELP

my $Usage = <<USAGE;
Usage: $0 -help to list options
USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;


# =============================================================================
# Arguments' validation
# =============================================================================
unless ( defined $dataset_name ) {
    print $Help;
    print "$Usage\n\tERROR: The dataset name needs to be provided. "
        . "It is required by the BIDS specifications to populate the "
        . "dataset_description.json file \n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}

unless ( defined $profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
        . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}


# =============================================================================
# Database connection + Get config settings
# =============================================================================
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\n==> Successfully connected to database \n";

# Get settings from the ConfigSettings table
my $data_dir = &NeuroDB::DBI::getConfigSetting(\$dbh,'dataDirBasepath');
my $bin_dir  = &NeuroDB::DBI::getConfigSetting(\$dbh,'MRICodePath');
my $prefix   = &NeuroDB::DBI::getConfigSetting(\$dbh,'prefix');

# remove trailing / from paths
$data_dir =~ s/\/$//g;
$bin_dir  =~ s/\/$//g;


# =============================================================================
# Create destination directory for the BIDS dataset
# It will be at the same level as the assembly directory and named BIDS_export
# =============================================================================
my $dest_dir = "$data_dir/BIDS_export";
make_path($dest_dir) unless (-d $dest_dir);
# Append to the destination directory name
$dest_dir   = $dest_dir . "/" . $dataset_name;
my $message = "\nNOTE: Directory $dest_dir already exists.\n"
              . "\t==> APPENDING new candidates and OVERWRITING EXISTING ONES\n";
(-d $dest_dir) ? print $message : make_path($dest_dir);


# =============================================================================
# Get the LORIS-MRI version number from the VERSION file
# =============================================================================
my $loris_mri_version;
my $version_file = "$bin_dir/VERSION";
open(my $fh, '<', $version_file) or die "cannot open file $version_file";
{
    local $/;
    $loris_mri_version = <$fh>;
    $loris_mri_version =~ s/\n//g;
}
close($fh);


# =============================================================================
# Create the dataset_description.json BIDS file if it does not already exist
# =============================================================================
my $data_desc_filename  = "dataset_description.json";
my $data_desc_file_path = "$dest_dir/$data_desc_filename";
my %dataset_desc_hash   = (
    'BIDSVersion'           => $BIDS_VERSION,
    'Name'                  => $dataset_name,
    'LORISScriptVersion'    => $LORIS_SCRIPT_VERSION,
    'Authors'               => @AUTHORS,
    'HowToAcknowledge'      => $ACKNOWLEDGMENTS,
    'LORISReleaseVersion'   => $loris_mri_version
);
unless (-e $data_desc_file_path) {
    print "\n******* Creating the dataset description file $data_desc_file_path *******\n";
    write_BIDS_JSON_file($data_desc_file_path, \%dataset_desc_hash);
    registerBidsFileInDatabase(
        $data_desc_file_path, 'study', 'json', undef, undef, 'dataset_description', undef
    );
}


# =============================================================================
# Create the README BIDS file if it does not already exist
# =============================================================================
my $readme_file_path = $dest_dir . "/README";
unless (-e $readme_file_path) {
    print "\n******* Creating the README file $readme_file_path *******\n";
    write_BIDS_TEXT_file($readme_file_path, $README);
    registerBidsFileInDatabase(
        $readme_file_path, 'study', 'README', undef, undef, 'README', undef
    );
}


# =============================================================================
# Create a .gitignore file for the BIDS validator to ignore some of the checks
# expected to not pass (some file types not yet officially released in the BIDS
# specifications, not the same number of files per session etc...)
# =============================================================================
my $bids_validator_config_file = $dest_dir . "/.bids-validator-config.json";
unless (-e $bids_validator_config_file) {
    print "\n******* Creating the .bids-validator-config.json file $bids_validator_config_file *******\n";
    write_BIDS_TEXT_file($bids_validator_config_file, $BIDS_VALIDATOR_CONFIG);
    registerBidsFileInDatabase(
        $bids_validator_config_file, 'study', 'json', undef, undef, 'bids-validator-config', undef
    );
}


# =============================================================================
# Query the tarchive table to get the list of TarchiveIDs to process
# =============================================================================
my $query = "SELECT DISTINCT TarchiveID FROM tarchive";
$query   .= " WHERE TarchiveID = ? " if defined $tarchive_id ;

my $sth = $dbh->prepare($query);
(defined $tarchive_id) ? $sth->execute($tarchive_id) : $sth->execute();


# =============================================================================
# Loop through the list of TarchiveID to process and convert them into BIDS
# =============================================================================
while ( my $rowhr = $sth->fetchrow_hashref()) {
    my $queried_tarchive_id = $rowhr->{'TarchiveID'};
    $message = "\n\n===========================================================\n"
               . "== Currently creating a BIDS directory for TarchiveID $queried_tarchive_id ==\n"
               . "===========================================================\n\n";
    print $message;

    # Grep the list of MINC files generated for that TarchiveID
    my %file_list = &getFileList($dbh, $queried_tarchive_id);

    # Create NIfTI and JSON files and return the list of phase files
    my $phasediff_list = &makeNIIAndHeader($dbh, %file_list);

    # Update the IntendedFor field for fieldmap phasediff JSON files if phasediff files were created
    &updateFieldmapIntendedFor(\%file_list, $phasediff_list) if keys %$phasediff_list;
}


# =============================================================================
# Print out final message to the user and clean up
# =============================================================================
if (defined $tarchive_id) {
    print "\n\nFinished processing TarchiveID $tarchive_id\n\n";
} else {
    print "\n\nFinished processing all tarchives\n\n";
}
$dbh->disconnect();
exit $NeuroDB::ExitCodes::SUCCESS;





# =============================================================================
# *****************************************************************************
# Script's functions
# *****************************************************************************
# =============================================================================

=pod

=head3 getFileList($db_handle, $givenTarchiveID)

Gets the list of MINC files associated to a given TarchiveID.

INPUTS:
    - $db_handle        : database handle
    - $given_tarchive_id: the C<TarchiveID> under consideration

RETURNS:
    - %file_list: hash with files and their information for a given C<TarchiveID>

    {
        "1" => {
            'fileID'                => 'FileID value',
            'file'                  => 'file path',
            'echoTime'              => 'Echo Time of the file',
            'AcquisitionProtocolID' => 'Scan type ID',
            'candID'                => 'Candidate CandID',
            'sessionID'             => 'Session ID',
            'visitLabel'            => 'Visit Label',
            'echoNumber'            => 'Echo Number of the scan',
            'seriesNumber'          => 'Series Number of the scan',
            'imageType'             => 'Image Type',
            'lorisScanType'         => 'LORIS Scan Type name'
        },
        "2" => {
            'fileID'                => 'FileID value',
            'file'                  => 'file path',
            'echoTime'              => 'Echo Time of the file',
            'AcquisitionProtocolID' => 'Scan type ID',
            'candID'                => 'Candidate CandID',
            'sessionID'             => 'Session ID',
            'visitLabel'            => 'Visit Label',
            'echoNumber'            => 'Echo Number of the scan',
            'seriesNumber'          => 'Series Number of the scan',
            'imageType'             => 'Image Type',
            'lorisScanType'         => 'LORIS Scan Type name'
        }
        ...
    }

=cut

sub getFileList {
    my ($db_handle, $given_tarchive_id) = @_;

    # Get ParameterTypeID for echo number, series number and image type headers
    my $echo_nb_param_type_id    = getParameterTypeID($db_handle, 'acquisition:echo_number');
    my $series_nb_param_type_id  = getParameterTypeID($db_handle, 'series_number');
    my $image_type_param_type_id = getParameterTypeID($db_handle, 'image_type');

    # Query to grep all file entries
    ### NOTE: parameter type hardcoded for open prevent ad...
    ( my $get_file_query = <<QUERY ) =~ s/\n/ /g;
SELECT
  f.FileID,
  File,
  AcquisitionProtocolID,
  EchoTime,
  c.CandID,
  s.Visit_label,
  f.SessionID,
  pf_echonb.Value as EchoNumber,
  pf_seriesnb.Value as SeriesNumber,
  pf_imagetype.Value as ImageType,
  mst.Scan_type AS LorisScanType
FROM files f
JOIN session s         ON (s.ID        = f.SessionID)
JOIN candidate c       ON (c.CandID    = s.CandID)
JOIN mri_scan_type mst ON (mst.ID      = f.AcquisitionProtocolID)
JOIN tarchive t        ON (t.SessionID = s.ID)
LEFT JOIN parameter_file pf_echonb    ON (f.FileID=pf_echonb.FileID)    AND pf_echonb.ParameterTypeID    = ?
LEFT JOIN parameter_file pf_seriesnb  ON (f.FileID=pf_seriesnb.FileID)  AND pf_seriesnb.ParameterTypeID  = ?
LEFT JOIN parameter_file pf_imagetype ON (f.FileID=pf_imagetype.FileID) AND pf_imagetype.ParameterTypeID = ?
WHERE f.OutputType IN ('native', 'defaced')
AND f.FileType       = 'mnc'
AND c.Entity_type    = 'Human'
AND t.TarchiveID = ?
QUERY

    # Prepare and execute query
    my $st_handle = $db_handle->prepare($get_file_query);
    $st_handle->execute(
        $echo_nb_param_type_id, $series_nb_param_type_id, $image_type_param_type_id, $given_tarchive_id
    );

    # Create file list hash with ID and relative location
    my %file_list;
    my $i = 0;
    while ( my $rowhr = $st_handle->fetchrow_hashref()) {
        $file_list{$i}{'fileID'}                = $rowhr->{'FileID'};
        $file_list{$i}{'file'}                  = $rowhr->{'File'};
        $file_list{$i}{'AcquisitionProtocolID'} = $rowhr->{'AcquisitionProtocolID'};
        $file_list{$i}{'candID'}                = $rowhr->{'CandID'};
        $file_list{$i}{'sessionID'}             = $rowhr->{'SessionID'};
        $file_list{$i}{'visitLabel'}            = $rowhr->{'Visit_label'};
        $file_list{$i}{'echoNumber'}            = $rowhr->{'EchoNumber'};
        $file_list{$i}{'echoNumber'}            =~ s/\.$//g if $file_list{$i}{'echoNumber'};  # remove trailing dot of the echo number
        $file_list{$i}{'seriesNumber'}          = $rowhr->{'SeriesNumber'};
        $file_list{$i}{'imageType'}             = $rowhr->{'ImageType'};
        $file_list{$i}{'lorisScanType'}         = $rowhr->{'LorisScanType'};
        $i++;
    }

    return %file_list;
}


=pod

=head3 getParameterTypeID($db_handle, $parameter_type_name)

Greps the ParameterTypeID value for a given parameter type.

INPUTS:
    - $db_handle          : database handle
    - $parameter_type_name: name of the parameter type to query

OUTPUT:
    - ParameterTypeID found for the parameter type

=cut

sub getParameterTypeID {
    my ($db_handle, $parameter_type_name) = @_;

    my $pt_query = "SELECT ParameterTypeID FROM parameter_type WHERE Name = ?";

    # Prepare and execute query
    my $st_handle = $db_handle->prepare($pt_query);
    $st_handle->execute($parameter_type_name);

    my $rowhr = $st_handle->fetchrow_hashref();

    return $rowhr->{'ParameterTypeID'};
}


=pod

=head3 determine_run_number(%file_list)

Determines the run number to associate with the scan and adds it to the
%file_list hash information for a given file.

Note: the run number is determined based on the seriesNumber field of the
session since the MINC number might not always have been attributed
sequentially when running the insertion pipeline.

INPUT:
    - %file_list: hash with images information associated with a tarchive

=cut

sub determine_run_number {
    my (%file_list) = @_;

    my @scan_types;
    for my $hash_id (keys %file_list) {
        my $scan_type = $file_list{$hash_id}{'lorisScanType'};
        $scan_type =~ s/-defaced//g;
        push(@scan_types, $scan_type) unless ( grep /^$scan_type$/, @scan_types);
    }

    for my $scan_type (@scan_types) {
        my @list_of_scans_with_scan_type;

        # grep the hash_id, scan type and series number information and
        # organize that information into an array to be able to sort by series
        # number and be able to determine the scan number
        for my $hash_id (keys %file_list) {
            next unless $file_list{$hash_id}{'lorisScanType'} =~ /^$scan_type(-defaced)?$/;
            my $series_number = $file_list{$hash_id}{'seriesNumber'};
            push (
                @list_of_scans_with_scan_type,
                {
                    'seriesNumber' => $series_number,
                    'hash_id'      => $hash_id,
                    'scan_type'    => $file_list{$hash_id}{'lorisScanType'}
                }
            );
        }

        # sort the list of files per seriesNumber for the scan type
        my @sorted_list_of_scans = sort { $a->{'seriesNumber'} <=> $b->{'seriesNumber'} } @list_of_scans_with_scan_type;

        # determine the run number for each file
        my $i = 1;
        for my $row (@sorted_list_of_scans) {
            my $hash_id = $row->{'hash_id'};
            $file_list{$hash_id}{'run_number'} = "00$i";
            $i++;
        }
    }
}


=pod

=head3 makeNIIAndHeader($db_handle, %file_list)

This function converts the MINC files into NIfTI files that will be organized
in a BIDS structure.
It also creates a .json file for each NIfTI file by getting the header values
from the C<parameter_file> table. Header information is selected based on the
BIDS document
(L<BIDS specifications|http://bids.neuroimaging.io/bids_spec1.0.2.pdf>; page
14 through 17).

INPUTS:
    - $db_handle: database handle
    - %file_list: hash with files' information.

OUTPUT:
    - %phasediff_seriesnb_hash: hash containing information regarding which
                                fieldmap should be associated to which
                                functional or DWI scan to be added in the
                                sidecar JSON file of the fieldmaps.

=cut

sub makeNIIAndHeader {
    my ( $db_handle, %file_list) = @_;

    my %phasediff_seriesnb_hash;
    foreach my $row (keys %file_list) {
        my $file_id         = $file_list{$row}{'fileID'};
        my $minc            = $file_list{$row}{'file'};
        my $minc_basename   = basename($minc);
        my $acq_protocol_id = $file_list{$row}{'AcquisitionProtocolID'};
        my $loris_scan_type = $file_list{$row}{'lorisScanType'};
        my $session_id      = $file_list{$row}{'sessionID'};

        ### check if the MINC file can be found on the file system
        my $minc_full_path = "$data_dir/$minc";
        unless (-e $minc_full_path) {
            print "\nCould not find the following MINC file: $minc_full_path\n" if defined $verbose ;
            next;
        }

        ### Get the BIDS scans label information
        my ($bids_categories_hash) = grep_bids_scan_categories_from_db($db_handle, $acq_protocol_id);
        unless (defined $bids_categories_hash) {
            my $basename = basename($minc);
            print "WARNING: skipping $basename since $loris_scan_type is not listed in bids_mri_scan_type_rel.\n";
            next;
        }
        $file_list{$row}{'BIDSScanType'}     = $bids_categories_hash->{'BIDSScanType'};
        $file_list{$row}{'BIDSCategoryName'} = $bids_categories_hash->{'BIDSCategoryName'};

        ### skip if BIDS scan type contains magnitude since they will be created
        ### when taking care of the phasediff fieldmap
        my $bids_scan_type   = $bids_categories_hash->{'BIDSScanType'};
        next if $bids_scan_type =~ m/magnitude/g;

        ### create an entry in participants.tsv file if it was not already created
        add_entry_in_participants_bids_file($file_list{$row}, $dest_dir, $db_handle);

        ### determine the BIDS NIfTI filename
        my $nifti_filename = determine_bids_nifti_file_name(
            $minc, $prefix, $file_list{$row}, $bids_categories_hash, $file_list{$row}{'run_number'}
        );

        ### create the BIDS directory where the NIfTI file would go
        my $bids_scan_directory = determine_BIDS_scan_directory(
            $file_list{$row}, $bids_categories_hash, $dest_dir
        );
        make_path($bids_scan_directory) unless(-d  $bids_scan_directory);

        ### Convert the MINC file into the BIDS NIfTI file
        print "\n\n******* Currently processing $minc_full_path ********\n\n";
        #  mnc2nii command then gzip it because BIDS expects it this way
        my $success = create_nifti_bids_file(
            $data_dir, $minc, $bids_scan_directory, $nifti_filename, $file_id
        );
        unless (defined $success) {
            print "WARNING: mnc2nii conversion failure for $minc_basename.\n";
            next;
        }

        # determine JSON filename
        my ($json_filename, $json_fullpath) = determine_BIDS_scan_JSON_file_path(
            $nifti_filename, $bids_scan_directory
        );
        $file_list{$row}{'niiFileName'}  = "$nifti_filename.gz";
        $file_list{$row}{'niiFilePath'}  = "$bids_scan_directory/$nifti_filename.gz";
        $file_list{$row}{'jsonFilePath'} = $json_fullpath;

        #  determine JSON information from MINC files header;
        my ($header_hash) = gather_parameters_for_BIDS_JSON_file(
            $minc_full_path, $json_filename, $bids_categories_hash
        );

        # for phasediff files, replace EchoTime by EchoTime1 and EchoTime2
        # and create the magnitude files associated with it
        if ($bids_scan_type =~ m/phasediff/i) {
            my $series_number = $file_list{$row}{'seriesNumber'};
            $phasediff_seriesnb_hash{$series_number}{'jsonFilePath'} = $json_fullpath;
            delete($header_hash->{'EchoTime'});
            my (%magnitude_files_hash) = grep_phasediff_associated_magnitude_files(
                \%file_list, $file_list{$row}, $db_handle
            );
            foreach my $echo_number (keys %magnitude_files_hash) {
                $echo_number =~ s/^Echo//;
                $header_hash->{"EchoTime$echo_number"} = $magnitude_files_hash{"Echo$echo_number"};
            }
            create_BIDS_magnitude_files($nifti_filename, \%magnitude_files_hash);
        }

        unless (-e $json_fullpath) {
            write_BIDS_JSON_file($json_fullpath, $header_hash);
            my $modalitytype = $bids_categories_hash->{'BIDSCategoryName'};
            registerBidsFileInDatabase($json_fullpath, 'image', 'json', $file_id, $modalitytype, undef, undef);
        }

        # DWI files need 2 extra special files; .bval and .bvec
        create_DWI_bval_bvec_files($bids_scan_directory, $nifti_filename, $file_id) if ($bids_scan_type eq 'dwi');

        ### add an entry in the sub-xxx_scans.tsv file with age
        my $nifti_full_path = "$bids_scan_directory/$nifti_filename";
        add_entry_in_scans_tsv_bids_file($file_list{$row}, $dest_dir, $nifti_full_path, $session_id, $db_handle);
    }

    return \%phasediff_seriesnb_hash;
}


=pod

=head3 grep_bids_scan_categories_from_db($db_handle, $acq_protocol_id)

Queries the bids tables in conjunction with the scan type table to
obtain the mapping between the acquisition protocol of the MINC files
and the BIDS scan labelling scheme to be used.

INPUT:
    - $db_handle      : database handle
    - $acq_protocol_id: acquisition protocol ID of the MINC file

OUTPUT:
    - $rowhr: hash with the BIDS scan type information.

    {
        'MRIScanTypeID'           => 'acquisition protocol ID of the MINC file',
        'BIDSCategoryName'        => 'BIDS category to use for the NIfTI file, aka anat, func, fmap, dwi...',
        'BIDSScanTypeSubCategory' => 'BIDS subcategory to use for the NIfTI file, aka task-rest, task-memory...',
        'BIDSEchoNumber'          => 'Echo Number associated with the NIfTI file',
        'Scan_type'               => 'label of the LORIS Scan type from the mri_scan_type table'
    }

Note: BIDSEchoNumber and BIDSScanTypeSubCategory can be null for a given NIfTI file.

=cut

sub grep_bids_scan_categories_from_db {
    my ($db_handle, $acq_protocol_id) = @_;

    # Get the scan category (anat, func, dwi, to know which subdirectory to place files in
    ( my $bids_query = <<QUERY ) =~ s/\n/ /g;
SELECT
  bmstr.MRIScanTypeID,
  bids_category.BIDSCategoryName,
  bids_scan_type_subcategory.BIDSScanTypeSubCategory,
  bids_scan_type.BIDSScanType,
  bmstr.BIDSEchoNumber,
  bids_phase_encoding_direction.BIDSPhaseEncodingDirectionName,
  mst.Scan_type
FROM bids_mri_scan_type_rel bmstr
  JOIN      mri_scan_type mst             ON mst.ID = bmstr.MRIScanTypeID
  JOIN      bids_category                 USING (BIDSCategoryID)
  JOIN      bids_scan_type                USING (BIDSScanTypeID)
  LEFT JOIN bids_scan_type_subcategory    USING (BIDSScanTypeSubCategoryID)
  LEFT JOIN bids_phase_encoding_direction USING (BIDSPhaseEncodingDirectionID)
WHERE
  mst.ID = ?
QUERY
    # Prepare and execute query
    my $st_handle = $db_handle->prepare($bids_query);
    $st_handle->execute($acq_protocol_id);
    my $rowhr = $st_handle->fetchrow_hashref();

    return $rowhr;
}


=pod

=head3 create_nifti_bids_file($data_basedir, $minc_path, $bids_dir, $nifti_name, $file_id, $modality_type)

Convert the MINC file into a NIfTI file labelled and organized according to the BIDS specifications.

INPUTS:
    - $data_basedir : base data directory (where the assembly and BIDS_export directories are located)
    - $minc_path    : relative path to the MINC file
    - $bids_dir     : relative path to the BIDS directory where the NIfTI file should be created
    - $nifti_name   : name to give to the NIfTI file
    - $file_id      : FileID of the MINC file in the files table
    - $modality_type: BIDS modality type or category (a.k.a. 'anat', 'func', 'fmap'...)

OUTPUT:
    - relative path to the created NIfTI file

=cut

sub create_nifti_bids_file {
    my ($data_basedir, $minc_path, $bids_dir, $nifti_name, $file_id, $modality_type) = @_;

    return 1 if -e "$bids_dir/$nifti_name.gz";

    my $cmd = "mnc2nii -nii -quiet $data_basedir/$minc_path $bids_dir/$nifti_name";
    system($cmd);

    my $gz_cmd = "gzip -f $bids_dir/$nifti_name";
    system($gz_cmd);

    registerBidsFileInDatabase("$bids_dir/$nifti_name.gz", 'image', 'nii', $file_id, $modality_type, undef, undef);

    return -e "$bids_dir/$nifti_name.gz";
}


=pod

=head3 determine_bids_nifti_file_name($minc, $loris_prefix, $minc_file_hash, $bids_label_hash, $run_nb, $echo_nb)

Determines the BIDS NIfTI file name to be used when converting the MINC file into a BIDS
compatible NIfTI file.

INPUTS:
    - $minc           : relative path to the MINC file
    - $loris_prefix   : LORIS prefix used to name the MINC file
    - $minc_file_hash : hash with candidate, visit label & scan type information associated with the MINC file
    - $bids_label_hash: hash with the BIDS labelling information corresponding to the MINC file's scan type.
    - $run_nb         : run number to use to label the NIfTI file to be created
    - $echo_nb        : echo number to use to label the NIfTI file to be created (can be undefined)

OUTPUT:
    - $nifti_name: name of the NIfTI file that will be created

=cut

sub determine_bids_nifti_file_name {
    my ($minc, $loris_prefix, $minc_file_hash, $bids_label_hash, $run_nb, $echo_nb) = @_;

    # grep LORIS information used to label the MINC file
    my $candID            = $minc_file_hash->{'candID'};
    my $loris_visit_label = $minc_file_hash->{'visitLabel'};
    my $loris_scan_type   = $bids_label_hash->{'Scan_type'};

    # grep the different BIDS information to use to name the NIfTI file
    my $bids_category    = $bids_label_hash->{BIDSCategoryName};
    my $bids_subcategory = $bids_label_hash->{BIDSScanTypeSubCategory};
    my $bids_scan_type   = $bids_label_hash->{BIDSScanType};
    my $bids_echo_nb     = $bids_label_hash->{BIDSEchoNumber};

    # determine the NIfTI name based on the MINC name
    my $nifti_name = basename($minc);
    $nifti_name =~ s/mnc$/nii/;

    # remove _ that could potentially be in the LORIS visit label
    my $bids_visit_label = $loris_visit_label;
    $bids_visit_label =~ s/_//g;

    # replace LORIS specifics with BIDS naming
    my $remove = "$loris_prefix\_$candID\_$loris_visit_label";
    my $replace = "sub-$candID\_ses-$bids_visit_label";
    # sequences with multi-echo need to have echo-1, echo-2, etc... appended to the filename
    if (defined $bids_echo_nb) {
        $replace .= "_echo-$bids_echo_nb";
    }
    $nifti_name =~ s/$remove/$replace/g;

    # if the LORIS scan type contain the -defaced string add more string
    # manipulation to determine the BIDS NIfTI filename
    if ($loris_scan_type =~ m/-defaced$/) {
        # remove the defaced part of the file name
        $nifti_name =~ s/_$loris_scan_type\_\d\d\d//g;
        # remove -defaced string from the loris_scan_type
        $loris_scan_type =~ s/-defaced$//g;
    }

    # make the filename have the BIDS Scan type name, in case the project Scan type name is not compliant;
    # and append the word 'run' before run number.
    # If the file is of type fMRI; need to add a BIDS subcategory type for example, task-rest for resting state fMRI
    # or task-memory for memory task fMRI
    if ($bids_category eq 'func') {
        if ($bids_label_hash->{BIDSScanTypeSubCategory}) {
            $replace = $bids_subcategory . "_run-";
        } else {
            print STDERR "\n ERROR: Files of BIDS Category type 'func' and which are fMRI need to have their"
                          . " BIDSScanTypeSubCategory defined. \n\n";
            exit $NeuroDB::ExitCodes::PROJECT_CUSTOMIZATION_FAILURE;
        }
    } elsif ($bids_scan_type eq 'dwi') {
        if ($bids_label_hash->{BIDSScanTypeSubCategory}) {
            $replace = $bids_subcategory . "_run-";
        } else {
            $replace = "run-";
        }
    } else {
        $replace = "run-";
    }
    $remove     = "$loris_scan_type\_";
    $nifti_name =~ s/$remove/$replace/g;

    if ($bids_scan_type eq 'magnitude' && $run_nb && $echo_nb) {
        # use the same run number as the phasediff
        $nifti_name =~ s/run-\d\d\d/$run_nb/g;
        # if echo number is provided, then modify name of the magnitude files
        # to be magnitude1 or magnitude2 depending on the echo number
        if (defined $echo_nb) {
            $bids_scan_type .= $echo_nb;
        }
    } elsif (defined $run_nb) {
        $nifti_name =~ s/run-\d\d\d/run-$run_nb/g;
    }

    # find position of the last dot of the NIfTI file, where the extension starts
    my ($base, $path, $ext) = fileparse($nifti_name, qr{\..*});
    $nifti_name = $base . "_" . $bids_scan_type . $ext;

    return $nifti_name;
}


=pod

=head3 add_entry_in_participants_bids_file($minc_file_hash, $bids_root_dir, $db_handle)

Adds an entry in the participants.tsv BIDS file for a given candidate.

INPUTS:
    - $minc_file_hash: hash with information associated to the MINC file
    - $bids_root_dir : path to the BIDS root directory
    - $db_handle     : database handle

=cut

sub add_entry_in_participants_bids_file {
    my ($minc_file_hash, $bids_root_dir, $db_handle) = @_;

    my $participants_tsv_file  = $bids_root_dir . '/participants.tsv';
    my $participants_json_file = $bids_root_dir . '/participants.json';

    my $cand_id = $minc_file_hash->{'candID'};

    if (! -e $participants_tsv_file) {
        # create the tsv and json file if they do not exist
        create_participants_tsv_and_json_file($participants_tsv_file, $participants_json_file);
        registerBidsFileInDatabase(
            $participants_tsv_file,  'study',                  'tsv',  undef,
            undef,                   'participants_list_file', undef
        );
        registerBidsFileInDatabase(
            $participants_json_file, 'study',                  'json', undef,
            undef,                   'participants_list_file', undef
        );
    } else {
        # read participants.tsv file and check if a row is already present for
        # that subject
        open (FH, '<:encoding(utf8)', $participants_tsv_file) or die " $!";
        while (my $row = <FH>) {
            return if ($row =~ m/^sub-$cand_id/);
        }
    }

    # grep the values to insert in the participants.tsv file
    my $values = grep_participants_values_from_db($db_handle, $cand_id);
    open (FH, '>>:encoding(utf8)', $participants_tsv_file) or die " $!";
    print FH (join("\t", @$_), "\n") for $values;
    close FH;
}


=pod

=head3 grep_participants_values_from_db($db_handle, $cand_id)

Gets participant's sex from the candidate table.

INPUTS:
    - $db_handle: database handle
    - $cand_id  : candidate ID

OUTPUT:
    - @values: array with values returned from the candidate table

=cut

sub grep_participants_values_from_db {
    my ($db_handle, $cand_id) = @_;

    ( my $candidate_query = <<QUERY ) =~ s/\n/ /g;
SELECT
  Sex,
  psc.Alias AS site,
  Project.Alias AS project
FROM candidate c
  JOIN psc ON (c.RegistrationCenterID=psc.CenterID)
  JOIN Project ON (c.RegistrationProjectID=Project.ProjectID)
WHERE CandID = ?
QUERY

    my $st_handle = $db_handle->prepare($candidate_query);
    $st_handle->execute($cand_id);

    my @values = $st_handle->fetchrow_array;
    unshift(@values, "sub-$cand_id");

    return \@values;
}


=pod

=head3 create_participants_tsv_and_json_file($participants_tsv_file, $participants_json_file)

Creates the BIDS participants.tsv and participants.json files in the root directory of the
BIDS structure. Note: the TSV file will only contain participant_id and sex information.

INPUTS:
    - $participants_tsv_file : BIDS participants TSV file
    - $participants_json_file: BIDS participants JSON file

=cut

sub create_participants_tsv_and_json_file {
    my ($participants_tsv_file, $participants_json_file) = @_;

    # create participants.tsv file
    my @header_row = ['participant_id', 'sex', 'site', 'project'];
    open(FH, ">:encoding(utf8)", $participants_tsv_file) or die " $!";
    print FH (join("\t", @$_), "\n") for @header_row;
    close FH;

    # create participants.json file
    my %header_dict = (
        'sex'     => {
            'Description' => 'sex of the participant',
            'Levels'      => { 'Male' => 'Male', 'Female' => 'Female' }
        },
        'site'    => {
            'Description' => "site of the participant"
        },
        'project' => {
            'Description' => "project of the participant"
        }
    );
    write_BIDS_JSON_file($participants_json_file, \%header_dict);
}


=pod

=head3 add_entry_in_scans_tsv_bids_file($minc_file_hash, $bids_root_dir, $nifti_full_path, $session_id, $db_handle)

Adds an entry in the session level BIDS scans.tsv file.

INPUTS:
    - $minc_file_hash : hash with information about the MINC file
    - $bids_root_dir  : BIDS root directory path
    - $nifti_full_path: full path to the BIDS NIfTI file to add in the TSV file
    - $session_id     : session ID in the session table
    - $db_handle      : database handle

=cut

sub add_entry_in_scans_tsv_bids_file {
    my ($minc_file_hash, $bids_root_dir, $nifti_full_path, $session_id, $db_handle) = @_;

    my $bids_sub_id = "sub-$minc_file_hash->{'candID'}";
    my $bids_ses_id = "ses-$minc_file_hash->{'visitLabel'}";

    my $bids_scans_rootdir   = "$bids_root_dir/$bids_sub_id/$bids_ses_id";
    my $bids_scans_tsv_file  = "$bids_scans_rootdir/$bids_sub_id\_$bids_ses_id\_scans.tsv";
    my $bids_scans_json_file = "$bids_scans_rootdir/$bids_sub_id\_$bids_ses_id\_scans.json";

    # determine the filename entry to be added to the TSV file
    my $filename_entry = "$nifti_full_path.gz";
    $filename_entry    =~ s/$bids_scans_rootdir\///g;

    unless (-e $bids_scans_tsv_file) {
        # create the tsv and json file if they do not exist
        create_scans_tsv_and_json_file($bids_scans_tsv_file, $bids_scans_json_file);
        registerBidsFileInDatabase(
            $bids_scans_tsv_file, 'session', 'tsv', undef, undef, 'session_list_of_scans', $session_id
        );
        registerBidsFileInDatabase(
            $bids_scans_json_file, 'session', 'json', undef, undef, 'session_list_of_scans', $session_id
        );
    } else {
        # read scans.tsv file and check if a row is already present for that scan
        open (FH, '<:encoding(utf8)', $bids_scans_tsv_file) or die " $!";
        while (my $row = <FH>) {
            return if ($row =~ m/^$filename_entry/);
        }
    }

    # grep the values to insert in the scans.tsv file
    my $cand_id     = $minc_file_hash->{'candID'};
    my $visit_label = $minc_file_hash->{'visitLabel'};
    my $values      = grep_age_values_from_db($db_handle, $cand_id, $visit_label, $filename_entry);
    open (FH, '>>:encoding(utf8)', $bids_scans_tsv_file) or die " $!";
    print FH (join("\t", @$_), "\n") for $values;
    close FH;
}


=pod

=head3 create_scans_tsv_and_json_file($scans_tsv_file, $scans_json_file)

Creates the BIDS session level scans.tsv and scans.json files of the BIDS structure.
Note: the TSV file will only contain filename and candidate_age_at_acquisition information for now.

INPUTS:
    - $scans_tsv_file : BIDS session level scans TSV file
    - $scans_json_file: BIDS session level scans JSON file

=cut

sub create_scans_tsv_and_json_file {
    my ($scans_tsv_file, $scans_json_file) = @_;

    # create participants.tsv file
    my @header_row = [ 'filename', 'candidate_age_at_acquisition' ];
    open(FH, ">:encoding(utf8)", $scans_tsv_file) or die " $!";
    print FH (join("\t", @$_), "\n") for @header_row;
    close FH;

    # create participants.json file
    my %header_dict = (
        'candidate_age_at_acquisition' => {
            'Description' => 'candidate age in months at the time of acquisition',
            'Units'       => 'Months'
        }
    );
    write_BIDS_JSON_file($scans_json_file, \%header_dict);
}


=pod

=head3 grep_age_values_from_db($db_handle, $cand_id, $visit_label, $filename_entry)

Gets the age of the candidate at the time of the acquisition from the session table.

INPUTS:
    - $db_handle     : database handle
    - $cand_id       : candidate ID
    - $visit_label   : visit label
    - $filename_entry: filename to be associated with the age found

OUTPUT:
    - @values: values associated with that filename

=cut

sub grep_age_values_from_db {
    my ($db_handle, $cand_id, $visit_label, $filename_entry) = @_;

    ( my $age_query = <<QUERY ) =~ s/\n/ /g;
SELECT
  TIMESTAMPDIFF(MONTH, DoB, Date_visit)
FROM
  candidate
  JOIN session USING (CandID)
WHERE
  CandID = ? AND Visit_label = ?;
QUERY

    my $st_handle = $db_handle->prepare($age_query);
    $st_handle->execute($cand_id, $visit_label);

    my @values = $st_handle->fetchrow_array;
    unshift(@values, $filename_entry);

    return \@values;
}

sub determine_BIDS_scan_directory {
    my ($minc_file_hash, $bids_label_hash, $bids_root_dir) = @_;

    # grep LORIS information used to label the MINC file
    my $candID      = $minc_file_hash->{'candID'};
    my $visit_label = $minc_file_hash->{'visitLabel'};
    $visit_label    =~ s/_//g; # remove _ that could potentially be in the LORIS visit label

    # grep the BIDS category that will be used in the BIDS path
    my $bids_category = $bids_label_hash->{BIDSCategoryName};

    my $bids_scan_directory = "$bids_root_dir/sub-$candID/ses-$visit_label/$bids_category";

    return $bids_scan_directory;
}


=pod

=head3 determine_BIDS_scan_JSON_file_path($nifti_name, $bids_scan_directory)

Determines the path of the JSON file accompanying the BIDS NIfTI file.

INPUTS:
    - $nifti_name         : name of the NIfTI file for which the JSON name needs to be determined
    - $bids_scan_directory: BIDS directory where the NIfTI and JSON files for the scan will go

OUTPUTS:
    - $json_filename: file name of the BIDS JSON side car file
    - $json_fullpath: full path of the BIDS JSON side car file

=cut

sub determine_BIDS_scan_JSON_file_path {
    my ($nifti_name, $bids_scan_directory) = @_;

    my $json_filename = $nifti_name;
    $json_filename    =~ s/nii/json/g;

    my $json_fullpath = "$bids_scan_directory/$json_filename";

    return ($json_filename, $json_fullpath);
}


=pod

=head3 write_BIDS_JSON_file($json_fullpath, $header_hash)

Write a BIDS JSON file based on the content of $header_hash.

INPUTS:
    - $json_fullpath: full path to the JSON file to create
    - $header_hash  : hash with the information to print into the JSON file

=cut

sub write_BIDS_JSON_file {
    my ($json_fullpath, $header_hash) = @_;

    my $json_obj            = JSON->new->allow_nonref;
    my $current_header_JSON = $json_obj->pretty->encode($header_hash);

    open HEADERINFO, ">$json_fullpath" or die "Can not write file $json_fullpath: $!\n";
    HEADERINFO->autoflush(1);
    select(HEADERINFO);
    select(STDOUT);
    print HEADERINFO "$current_header_JSON";
    close HEADERINFO;
}


=pod

=head3 write_BIDS_TEXT_file($filename, $content)

Write the content stored in $content into a given text file.

INPUTS:
    - $file_path: path to the file to write
    - $content  : content to be written in the text file

=cut

sub write_BIDS_TEXT_file {
    my ($file_path, $content) = @_;

    open FILE, ">$file_path" or die "Can not write file $file_path: $!\n";
    FILE->autoflush(1);
    select(FILE);
    select(STDOUT);
    print FILE "$content\n";
    close FILE;
}


=pod

=head3 create_DWI_bval_bvec_files($bids_scan_directory, $nifti_file_name, $file_id)

Creates BVAL and BVEC files associated to a DWI scan.

INPUTS:
    - $bids_scan_directory: directory where the BVAL and BVEC files should be created
    - $nifti_file_name    : name of the NIfTI file for which BVAL and BVEC files need to be created
    - $file_id            : file ID of the DWI scan from the files table

=cut

sub create_DWI_bval_bvec_files {
    my ($dest_dir_final, $nifti_file_name, $file_id) = @_;

    # Load MINC file information
    my $file_ref = NeuroDB::File->new(\$dbh);
    $file_ref->loadFile($file_id);

    # Create the .bval file
    my $bval_file_name = $nifti_file_name;
    $bval_file_name    =~ s/nii$/bval/g;
    my $success_bval   = NeuroDB::MRI::create_dwi_nifti_bval_file(\$file_ref, "$dest_dir_final/$bval_file_name");
    if (defined $success_bval) {
        registerBidsFileInDatabase("$dest_dir_final/$bval_file_name", 'image', 'bval', $file_id, 'dwi', undef, undef);
    } else {
        print "WARNING: .bval DWI file not created for " . basename($nifti_file_name) . "\n";
    }


    # Create the .bvec file
    my $bvec_file_name = $nifti_file_name;
    $bvec_file_name    =~ s/nii$/bvec/g;
    my $success_bvec   = NeuroDB::MRI::create_dwi_nifti_bvec_file(\$file_ref, "$dest_dir_final/$bvec_file_name");
    if (defined $success_bvec) {
        registerBidsFileInDatabase("$dest_dir_final/$bvec_file_name", 'image', 'bvec', $file_id, 'dwi', undef, undef);
    } else {
        print "WARNING: .bvec DWI file not created for " . basename($nifti_file_name) . "\n";
    }
}


=pod

=head3 gather_parameters_for_BIDS_JSON_file($minc_full_path, $json_filename, $bids_categories_hash)

Gathers the scan parameters to add into the BIDS JSON side car file.

INPUTS:
    - $minc_full_path      : full path to the MINC file with header information
    - $json_filename       : name of the BIDS side car JSON file where scan parameters will go
    - $bids_categories_hash: hash with the BIDS categories information

OUTPUT:
    - $header_hash: hash with the header information to insert into the BIDS JSON side car file

=cut

sub gather_parameters_for_BIDS_JSON_file {
    my ($minc_full_path, $json_filename, $bids_categories_hash) = @_;

    my ($header_hash) = grep_generic_header_info_for_JSON_file($minc_full_path, $json_filename);

    my $bids_category  = $bids_categories_hash->{'BIDSCategoryName'};
    my $bids_scan_type = $bids_categories_hash->{'BIDSScanType'};

    # for fMRI, we need to add TaskName which is e.g task-rest in the case of resting-state fMRI
    if ($bids_category eq 'func' && $bids_scan_type !~ m/asl/i) {
        grep_TaskName_info_for_JSON_file($bids_categories_hash, $header_hash);
    }

    # for 4D datasets, we need to add PhaseEncodingDirection and EffectiveEchoSpacing
    if ($bids_category eq 'func' || $bids_category eq 'asl' || $bids_category eq 'dwi') {
        my $phase_encoding_direction = $bids_categories_hash->{'BIDSPhaseEncodingDirectionName'};
        $header_hash->{'PhaseEncodingDirection'} = $phase_encoding_direction if defined $phase_encoding_direction;
        add_EffectiveEchoSpacing_and_TotalReadoutTime_info_for_JSON_file($header_hash, $minc_full_path);
    }

    # for MP2RAGE, we need to add RepetitionTimeExcitation
    if ($bids_scan_type eq 'MP2RAGE' || $bids_scan_type eq 'T1map' || $bids_scan_type eq 'UNIT1') {
        add_RepetitionTimeExcitation_info_for_JSON_file($header_hash, $minc_full_path);
    }

    return $header_hash;
}


=pod

=head3 grep_generic_header_info_for_JSON_file($minc_full_path, $json_filename)

Greps generic header information that applies to all scan types and map them to the BIDS ontology.

INPUTS:
    - $minc_full_path: full path to the MINC file
    - $json_filename : name of the BIDS JSON side car file

OUTPUT:
    - %header_hash: hash with scan's header information

=cut

sub grep_generic_header_info_for_JSON_file {
    my ($minc_full_path, $json_filename) = @_;

    # get this info from the MINC header instead of the database
    # Name is as it appears in the database. Note: slice order is needed for resting state fMRI
    my @minc_header_name_array = (
        'acquisition:repetition_time',   'study:manufacturer',
        'study:device_model',            'study:field_value',
        'study:serial_no',               'study:software_version',
        'acquisition:receive_coil',      'acquisition:scanning_sequence',
        'acquisition:echo_time',         'acquisition:inversion_time',
        'dicom_0x0018:el_0x1314',        'study:institution',
        'acquisition:slice_order',       'study:modality',
        'acquisition:imaging_frequency', 'patient:position',
        'dicom_0x0018:el_0x0023',        'acquisition:series_description',
        'acquisition:protocol',          'dicom_0x0018:el_0x0020',
        'dicom_0x0018:el_0x0021',        'dicom_0x0018:el_0x0024',
        'acquisition:image_type',        'dicom_0x0020:el_0x0011',
        'dicom_0x0020:el_0x0012',        'acquisition:slice_thickness',
        'acquisition:SAR',               'acquisition:phase_enc_dir',
        'acquisition:percent_phase_fov', 'acquisition:num_phase_enc_steps',
        'acquisition:pixel_bandwidth',   'dicom_0x0020:el_0x0037',
        'acquisition:echo_number'
    );
    # Equivalent name as it appears in the BIDS specifications
    my @bids_header_name_array = (
        "RepetitionTime",        "Manufacturer",
        "ManufacturerModelName", "MagneticFieldStrength",
        "DeviceSerialNumber",    "SoftwareVersions",
        "ReceiveCoilName",       "PulseSequenceType",
        "EchoTime",              "InversionTime",
        "FlipAngle",             "InstitutionName",
        "SliceOrder",            "Modality",
        "ImagingFrequency",      "PatientPosition",
        "MRAcquisitionType",     "SeriesDescription",
        "ProtocolName",          "ScanningSequence",
        "SequenceVariant",       "SequenceName",
        "ImageType",             "SeriesNumber",
        "AcquisitionNumber",     "SliceThickness",
        "SAR",                   "InPlanePhaseEncodingDirectionDICOM",
        "PercentPhaseFOV",       "PhaseEncodingSteps",
        "PixelBandwidth",        "ImageOrientationPatientDICOM",
        "EchoNumber"
    );

    my $manufacturerPhilips = 0;

    my (%header_hash);
    foreach my $j (0 .. scalar(@minc_header_name_array) - 1) {
        my $minc_header_name = $minc_header_name_array[$j];
        my $bids_header_name = $bids_header_name_array[$j];
        $bids_header_name    =~ s/^\"+|\"$//g;
        print "Adding now $bids_header_name header to info to write to $json_filename\n" if defined $verbose;

        my $header_value = NeuroDB::MRI::fetch_header_info($minc_full_path, $minc_header_name);

        # Some headers need to be explicitly converted to floats in Perl
        # so json_encode does not add the double quotation around them
        my @convert_to_float = (
            'acquisition:repetition_time',     'acquisition:echo_time',
            'acquisition:inversion_time',      'dicom_0x0018:el_0x1314',
            'acquisition:imaging_frequency',   'study:field_value',
            'dicom_0x0020:el_0x0011',          'dicom_0x0020:el_0x0012',
            'acquisition:slice_thickness',     'acquisition:SAR',
            'dicom_0x0018:el_0x1314',          'acquisition:percent_phase_fov',
            'acquisition:num_phase_enc_steps', 'acquisition:pixel_bandwidth',
            'acquisition:echo_number'
        );
        if (defined $header_value && $header_value =~ m/Binary file/) {
            $header_value = "not available, most like due to bad dcm2mnc conversion";
            print "WARNING: $minc_header_name is " . $header_value . "\n";
        } else {
            $header_value *= 1 if (defined $header_value && grep($minc_header_name eq $_, @convert_to_float));
            $header_value /= 1000000 if (defined $header_value && $minc_header_name eq 'acquisition:imaging_frequency');
            my @convert_to_array = [ 'acquisition:image_type', 'dicom_0x0020:el_0x0037' ];
            if (defined $header_value && grep(/^$minc_header_name$/, @convert_to_array)) {
                my @values = split("\\\\\\\\", $header_value);
                $header_value = \@values;
            }
        }

        if (defined $header_value) {
            $header_hash{$bids_header_name} = $header_value;
            print "     $bids_header_name was found for $minc_full_path with value $header_value\n" if defined $verbose;

            # If scanner is Philips, store this as condition 1 being met
            $manufacturerPhilips = 1 if ($minc_header_name eq 'study:manufacturer' && $header_value =~ /Philips/i);
        }
        else {
            print "     $bids_header_name was not found for $minc_full_path\n" if defined $verbose;
        }
    }

    grep_SliceOrder_info_for_JSON_file(\%header_hash, $minc_full_path, $manufacturerPhilips);

    return (\%header_hash);
}


=pod

=head3 add_EffectiveEchoSpacing_and_TotalReadoutTime_info_for_JSON_file($header_hash, $minc_full_path)

Logic to determine the EffectiveEchoSpacing and TotalReadoutTime parameters for functional, ASL and DWI
acquisitions.

INPUTS:
    - $header_hash   : hash with scan parameters that will be update with EffectiveEchoSpacing & TotalReadoutTime
    - $minc_full_path: full path to the MINC file

=cut

sub add_EffectiveEchoSpacing_and_TotalReadoutTime_info_for_JSON_file {
    my ($header_hash, $minc_full_path) = @_;

    # Conveniently, for Siemens’ data, this value is easily obtained as
    # 1/[BWPPPE * ReconMatrixPE], where BWPPPE is the "BandwidthPerPixelPhaseEncode
    # in DICOM tag (0019,1028) and ReconMatrixPE is the size of the actual
    # reconstructed data in the phase direction (which is NOT reflected in a
    # single DICOM tag for all possible aforementioned scan manipulations)
    my $bwpppe        = &NeuroDB::MRI::fetch_header_info($minc_full_path, 'dicom_0x0019:el_0x1028');
    my $reconMatrixPE = &NeuroDB::MRI::fetch_header_info($minc_full_path, 'dicom_0x0051:el_0x100b');
    $reconMatrixPE    =~ s/[a-z]?\*\d+[a-z]?//;

    # check that the header information returned as indeed numbers. Otherwise print message in the
    # console and the BIDS JSON file of the affected NIfTI file.
    unless ($bwpppe =~ m/^-?\d+\.?\d*$/ && $reconMatrixPE =~ m/^-?\d+\.?\d*$/) {
        my $basename = basename($minc_full_path);
        print "WARNING: Cannot compute EffectiveEchoSpacing & TotalReadoutTime for $basename\n"
              . "\t\t'dicom_0x0019:el_0x1028' should be a number. Its value is $bwpppe\n"
              . "\t\t'dicom_0x0051:el_0x100b' should be a number. Its value is $reconMatrixPE\n"
              . "\t\t=> This is unfortunately the result of a bad dcm2mnc conversion...\n";
        my $hdr_message = 'not supplied as the values read from the MINC header seem erroneous,'
                          . ' due most likely to a dcm2mnc conversion problem';
        $header_hash->{'EffectiveEchoSpacing'} = $hdr_message;
        $header_hash->{'TotalReadoutTime'}     = $hdr_message;
        return;
    }

    # compute the effective echo spacing
    my $effectiveEchoSpacing =  1 / ($bwpppe * $reconMatrixPE);
    $header_hash->{'EffectiveEchoSpacing'} = $effectiveEchoSpacing;

    # compute the total readout time
    # If EffectiveEchoSpacing has been properly computed, TotalReadoutTime is just
    # EffectiveEchoSpacing * (ReconMatrixPE - 1)
    $header_hash->{'TotalReadoutTime'} = $effectiveEchoSpacing * ($reconMatrixPE - 1)
}


=pod

=head3 add_RepetitionTimeExcitation_info_for_JSON_file($header_hash, $minc_full_path)

Get the RepetitionTimeExcitation parameter from the MINC header for MP2RAGE, T1map and UNIT1.

INPUTS:
    - $header_hash   : hash with scan parameters that will be update with RepetitionTimeExcitation
    - $minc_full_path: full path to the MINC file

=cut

sub add_RepetitionTimeExcitation_info_for_JSON_file {
    my ($header_hash, $minc_full_path) = @_;

    # RepetitionTimeExcitation is stored in DICOM field dicom_0x0018:el_0x0080
    my $reptimeexcitation = &NeuroDB::MRI::fetch_header_info($minc_full_path, 'dicom_0x0018:el_0x0080');

    $header_hash->{'RepetitionTimeExcitation'} = $reptimeexcitation / 1000;
}


=pod

=head3 grep_SliceOrder_info_for_JSON_file($header_hash, $minc_full_path, $manufacturer_philips)

Logic to determine the SliceOrder scan parameter for the BIDS JSON side car file.

INPUTS:
    - $header_hash          : hash with scan parameters that will be update with SliceOrder
    - $minc_full_path       : full path to the MINC file
    - $manufacturer_phillips: boolean stating whether the scanner is a Phillips device

=cut

sub grep_SliceOrder_info_for_JSON_file {
    my ($header_hash, $minc_full_path, $manufacturer_philips) = @_;

    my ($extra_header, $extra_header_val);
    my ($minc_header_name, $header_value);

    # If manufacturer is Philips, then add SliceOrder to the JSON manually
    ######## This is just for the BETA version #########
    ## See the TODO section for improvements needed in the future on SliceOrder ##
    if ($manufacturer_philips == 1) {
        $extra_header = "SliceOrder";
        $extra_header =~ s/^\"+|\"$//g;
        if ( defined $slice_order_philips ) {
            $extra_header_val = $slice_order_philips;
        }
        else {
            print "   This is a Philips Scanner with no $extra_header defined at the command line argument
                    '-slice_order_philips'. Setting SliceOrder as 'Not Supplied' in JSON file \n" if defined $verbose;
        }
        $header_hash->{$extra_header} = $extra_header_val;
        print "    $extra_header_val was added for Philips Scanners' $extra_header \n" if defined $verbose;
    }
    else {
        # get the SliceTiming from the proper header
        # split on the ',', remove trailing '.' if exists, and add [] to make it a list
        $minc_header_name = 'dicom_0x0019:el_0x1029';
        $extra_header = "SliceTiming";
        $header_value = &NeuroDB::MRI::fetch_header_info($minc_full_path, $minc_header_name);
        # Some earlier dcm2mnc converters created SliceTiming with values
        # such as 0b, -91b, -5b, etc... so those MINC headers with `b`
        # in them, do not report, just report that is it not supplied
        # due likely to a dcm2mnc error
        # print this message, even if NOT in verbose mode to let the user know
        if (defined $header_value) {
            if ($header_value =~ m/b/) {
                $header_value = "not supplied as the values read from the MINC header seem erroneous.\n"
                                . "\t\tThis is most likely due to a dcm2mnc conversion problem";
                print "WARNING: SliceTiming is " . $header_value . "\n";
            } else {
                $header_value = [ map {$_ / 1000} split(",", $header_value) ];
                print "    SliceTiming $header_value was added \n" if defined $verbose;
            }
        }
        $header_hash->{$extra_header} = $header_value;
    }
}


=pod

=head3 grep_TaskName_info_for_JSON_file($bids_categories_hash, $header_hash)

Greps the TaskName information derived from the BIDSScanTypeSubCategory for the BIDS JSON side car file.

INPUTS:
    - $bids_categories_hash: hash with BIDS category and sub category information
    - $header_hash: hash with scan parameters that will be update with TaskName

=cut

sub grep_TaskName_info_for_JSON_file {
    my ($bids_categories_hash, $header_hash) = @_;

    my ($extra_header, $extra_header_val);
    $extra_header = "TaskName";
    $extra_header =~ s/^\"+|\"$//g;
    # Assumes the SubCategory for funct BIDS categories in the BIDS
    # database tables follow the naming convention `task-rest` or `task-memory`,
    $extra_header_val = $bids_categories_hash->{'BIDSScanTypeSubCategory'};
    # so strip the `task-` part to get the TaskName
    # $extraHeaderVal =~ s/^task-//;
    # OR in general, strip everything up until and including the first hyphen
    $extra_header_val =~ s/^[^-]+\-//;
    $header_hash->{$extra_header} = $extra_header_val;
    print "    TASKNAME added for bold: $extra_header with value $extra_header_val\n" if defined $verbose;
}


=pod

=head3 grep_phasediff_associated_magnitude_files($loris_files_list, $phasediff_loris_hash, $db_handle)

Greps the magnitudes files associated with a given phasediff fieldmap scan file.

INPUTS:
    - $loris_files_list    : list of files extracted from LORIS for a given Tarchive
    - $phasediff_loris_hash: hash with phasediff fieldmap file information
    - $db_handle           : database handle

OUTPUT:
    - %magnitude_files: hash magnitude files associated to the phasediff fieldmap file

    {
        'Echo1' => 'magnitude file with echo number 1',
        'Echo2' => 'magnitude file with echo number 2'
    }

=cut

sub grep_phasediff_associated_magnitude_files {
    my ($loris_files_list, $phasediff_loris_hash, $db_handle) = @_;

    # grep phasediff session ID and series number to grep the corresponding
    # magnitude files
    my $phasediff_sessionID    = $phasediff_loris_hash->{'sessionID'};
    my $phasediff_seriesNumber = $phasediff_loris_hash->{'seriesNumber'};

    # fetch the acquisition protocol ID that corresponds to the magnitude files
    my $magnitude_acq_prot_id = grep_acquisitionProtocolID_from_BIDS_scan_type($db_handle, 'magnitude');

    my %magnitude_files;
    foreach my $row (keys %$loris_files_list) {
        my $acq_prot_id   = $loris_files_list->{$row}{'AcquisitionProtocolID'};
        my $session_id    = $loris_files_list->{$row}{'sessionID'};
        my $echo_number   = $loris_files_list->{$row}{'echoNumber'};
        my $series_number = $loris_files_list->{$row}{'seriesNumber'};

        # skip the row unless the file is a magnitude protocol of the same session with
        # the series number equal to the phasediff's series number - 1
        next unless ($acq_prot_id == $magnitude_acq_prot_id
            && $session_id == $phasediff_sessionID
            && $series_number == ($phasediff_seriesNumber - 1)
        );

        # add the different magnitude files to the magnitude_files hash
        # with their information based on their EchoNumber
        $magnitude_files{"Echo$echo_number"} = $loris_files_list->{$row};
    }

    return %magnitude_files;
}


=pod

=head3 grep_acquisitionProtocolID_from_BIDS_scan_type($db_handle, $bids_scan_type)

Greps the AcquisitionProtocolID associated to a BIDS magnitude file in the database.

INPUTS:
    - $db_handle     : database handle
    - $bids_scan_type: name of the BIDS scan type (for example: magnitude)

OUTPUT:
    - AcquisitionProtocolID associated to the BIDS scan type file in the database

=cut

sub grep_acquisitionProtocolID_from_BIDS_scan_type {
    my ($db_handle, $bids_scan_type) = @_;

    (my $scan_type_query = <<QUERY ) =~ s/\n/ /g;
SELECT
  mst.ID
FROM bids_mri_scan_type_rel bmstr
  JOIN mri_scan_type mst ON bmstr.MRIScanTypeID=mst.ID
  JOIN bids_scan_type bst USING (BIDSScanTypeID)
WHERE
  bst.BIDSScanType = ?
QUERY

    # Prepare and execute query
    my $st_handle = $db_handle->prepare($scan_type_query);
    $st_handle->execute($bids_scan_type);
    if ( $st_handle->rows > 0 ) {
        return $st_handle->fetchrow_array();
    } else {
        print "     no $bids_scan_type scan type was found in BIDS tables\n" if defined $verbose;
    }
}


=pod

=head3 create_BIDS_magnitude_files($phasediff_filename, $magnitude_files_hash)

Creates the BIDS magnitude files of fieldmap acquisitions.

INPUTS:
    - $phasediff_filename  : name of the BIDS fieldmap phasediff file
    - $magnitude_files_hash: hash with fieldmap associated magnitude files information

=cut

sub create_BIDS_magnitude_files {
    my ($phasediff_filename, $magnitude_files_hash) = @_;

    # grep the phasediff run number to be used for the magnitude file
    my $phasediff_run_nb;
    if ($phasediff_filename =~ m/_(run-\d\d\d)_/g) {
        $phasediff_run_nb = $1;
    } else {
        my $basename = basename($phasediff_filename);
        print "WARNING: could not find the run number for $basename\n";
    }

    foreach my $row (keys %$magnitude_files_hash) {
        my $minc        = $magnitude_files_hash->{$row}{'file'};
        my $acq_prot_id = $magnitude_files_hash->{$row}{'AcquisitionProtocolID'};
        my $echo_nb     = $magnitude_files_hash->{$row}{'echoNumber'};
        my $file_id     = $magnitude_files_hash->{$row}{'fileID'};

        ### check if the MINC file can be found on the file system
        my $minc_full_path = "$data_dir/$minc";
        if (! -e $minc_full_path) {
            print "\nCould not find the following MINC file: $minc_full_path\n" if defined $verbose;
            next;
        }

        ### Get the BIDS scans label information
        my ($bids_categories_hash) = grep_bids_scan_categories_from_db($dbh, $acq_prot_id);
        unless (defined $bids_categories_hash) {
            print basename($minc) . " will not be converted into BIDS as no entries were found "
                  . "in the bids_mri_scan_type_rel table for that scan type.\n";
            next;
        }

        ### determine the BIDS NIfTI filename
        my $nifti_filename = determine_bids_nifti_file_name(
            $minc, $prefix, $magnitude_files_hash->{$row}, $bids_categories_hash, $phasediff_run_nb, $echo_nb
        );

        ### create the BIDS directory where the NIfTI file would go
        my $bids_scan_directory = determine_BIDS_scan_directory(
            $magnitude_files_hash->{$row}, $bids_categories_hash, $dest_dir
        );
        make_path($bids_scan_directory) unless (-d  $bids_scan_directory);

        ### Convert the MINC file into the BIDS NIfTI file
        print "\n\n******* Currently processing $minc_full_path ********\n\n";
        #  mnc2nii command then gzip it because BIDS expects it this way
        my $success = create_nifti_bids_file(
            $data_dir, $minc, $bids_scan_directory, $nifti_filename, $file_id, $bids_categories_hash->{'BIDSCategoryName'}
        );
        unless (defined $success) {
            my $minc_basename = $minc;
            print "WARNING: mnc2nii conversion failed for $minc_basename.\n";
            next;
        }

        #  create json information from MINC files header;
        my ($json_filename, $json_fullpath) = determine_BIDS_scan_JSON_file_path($nifti_filename, $bids_scan_directory);

        my ($header_hash) = gather_parameters_for_BIDS_JSON_file(
            $minc_full_path, $json_filename, $bids_categories_hash
        );

        unless (-e $json_fullpath) {
            write_BIDS_JSON_file($json_fullpath, $header_hash);
            my $modality_type = $bids_categories_hash->{'BIDSCategoryName'};
            registerBidsFileInDatabase($json_fullpath, 'image', 'json', $file_id, $modality_type, undef, undef);
        }
    }
}


=pod

=head3 updateFieldmapIntendedFor($file_hash, $phasediff_list)

Updates the FieldmapIntendedFor field in the JSON side car with the list of
filenames the fieldmap should be applied on.

INPUTS:
    - $file_hash     : hash with all the files information
    - $phasediff_list: list of fieldmap phasediff files

=cut

sub updateFieldmapIntendedFor {
    my ($file_hash, $phasediff_list) = @_;

    my @list_of_fieldmap_seriesnb = keys %$phasediff_list;
    for my $row (keys %$file_hash) {
        my $series_number  = $file_hash->{$row}{'seriesNumber'};
        my $nii_filename   = $file_hash->{$row}{'niiFileName'};
        my $bids_scan_type = $file_hash->{$row}{'BIDSScanType'};
        my $bids_category  = $file_hash->{$row}{'BIDSCategoryName'};
        my $visit_label    = $file_hash->{$row}{'visitLabel'};

        next unless $bids_scan_type && $bids_scan_type =~ m/(bold)/;

        my $closest_fmap_seriesnb = getClosestNumberInArray($series_number, \@list_of_fieldmap_seriesnb);

        push @{ $phasediff_list->{$closest_fmap_seriesnb}{'IntendedForList'} }, "ses-$visit_label/$bids_category/$nii_filename";
    }

    ## modify JSON file to add the IntendedFor key
    for my $row (keys %$phasediff_list) {
        my $json_file    = $phasediff_list->{$row}{'jsonFilePath'};
        if ($phasediff_list->{$row}{'IntendedForList'}) {
            my @intended_for = @{ $phasediff_list->{$row}{'IntendedForList'} };
            # update the JSON file
            updateJSONfileWithIntendedFor($json_file, \@intended_for);
        }
    }
}


=pod

=head3 updateJSONfileWithIntendedFor($json_filepath, $intended_for)

Updates the IntendedFor header in the BIDS JSON file of a fieldmap acquisition.

INPUTS:
    - $json_filepath: path to the JSON file to update
    - $intended_for : list of file names to add to the IntendedFor JSON parameter

=cut

sub updateJSONfileWithIntendedFor {
    my ($json_filepath, $intended_for) = @_;

    # read the JSON file
    my $json_content = do {
        open(FILE, "<", $json_filepath) or die "Can not open $json_filepath: $!\n";
        local $/;
        <FILE>
    };
    close FILE;

    my $json_obj  = new JSON;
    my %json_data = %{ $json_obj->decode($json_content) };
    $json_data{'IntendedFor'} = $intended_for;
    write_BIDS_JSON_file($json_filepath, \%json_data);
}


=pod

=head3 getClosestNumberInArray($val, $arr)

Get the closest number to $val in an array.

INPUTS:
    - $val: value
    - $arr: array

OUTPUT:
    - the closest number to $val in array $arr

=cut

sub getClosestNumberInArray {
    my ($val, $arr) = @_;

    my @test = sort { abs($a - $val) <=> abs($b - $val)} @$arr;

    return $test[0];
}


=pod

=head3 registerBidsFileInDatabase($file_path, $file_level, $file_type, $file_id, $modality_type, $behavioural_type, session_id)

Registers the created BIDS files into the table bids_export_files with links to the FileID from the files table.

INPUTS:
    - $file_path       : path to the BIDS file to insert in the bids_export_files table
    - $file_level      : BIDS file level. One of 'study', 'image' or 'session'
    - $file_type       : BIDS file type. One of 'json', 'README', 'tsv', 'nii', 'bval', 'bvec', 'txt'
    - $file_id         : FileID of the associated MINC file from the files table
    - $modality_type   : BIDS modality of the file. One of 'fmap', 'asl', 'anat', 'dwi', 'func'.
                         'NULL' if the BIDS file to insert is not an acquisition file.
    - $behavioural_type: non-acquisition BIDS files type. One of 'dataset_description', 'README',
                         'bids-validator-config', 'participants_list_file', 'session_list_of_scans'.
                         'NULL' if the BIDS file to insert is an acquisition file.
    - $session_id      : session ID associated to the file to insert. 'NULL' if the file is at the BIDS study level

=cut

sub registerBidsFileInDatabase {
    my ($file_path, $file_level, $file_type, $file_id, $bids_img_category, $bids_bvl_category, $session_id) = @_;

    return unless (-e $file_path);

    my $file_level_id = get_BIDSExportFileLevelCategoryID($file_level);
    my $bvl_cat_id    = defined $bids_bvl_category ? get_BIDSNonImgFileCategoryID($bids_bvl_category) : undef;
    my $img_cat_id    = defined $bids_img_category ? get_BIDSCategoryID($bids_img_category) : undef;
    $file_path =~ s/$data_dir\///g;

    # check if there is already an entry for the file, if so return
    my $get_query = "SELECT BIDSExportedFileID FROM bids_export_files WHERE FilePath = ?";
    my $st_handle = $dbh->prepare($get_query);
    $st_handle->execute($file_path);

    (my $common_query_part = <<QUERY) =~ s/\n/ /g;
bids_export_files SET
    BIDSExportFileLevelID        = ?,
    FileID                       = ?,
    SessionID                    = ?,
    BIDSNonImagingFileCategoryID = ?,
    BIDSCategoryID               = ?,
    FileType                     = ?,
    FilePath                     = ?
QUERY
    my @values = ($file_level_id, $file_id, $session_id, $bvl_cat_id, $img_cat_id, $file_type, $file_path);

    if ($st_handle->rows > 0) {
        push @values, $st_handle->fetchrow_array();
        $query = "UPDATE $common_query_part WHERE BIDSExportFileID = ?";
    } else {
        $query = "INSERT INTO $common_query_part ";
    }
    $st_handle = $dbh->prepare($query);
    $st_handle->execute(@values);

}


sub get_BIDSNonImgFileCategoryID {
    my ($category_name) = @_;

    (my $get_query = <<QUERY ) =~ s/\n/ /g;
SELECT BIDSNonImagingFileCategoryID
FROM bids_export_non_imaging_file_category
WHERE BIDSNonImagingFileCategoryName = ?
QUERY

    my $st_handle = $dbh->prepare($get_query);
    $st_handle->execute($category_name);

    return $st_handle->rows > 0 ? $st_handle->fetchrow_array() : undef;
}


sub get_BIDSCategoryID {
    my ($category_name) = @_;

    my $get_query = "SELECT BIDSCategoryID FROM bids_category WHERE BIDSCategoryName = ?";
    my $st_handle = $dbh->prepare($get_query);
    $st_handle->execute($category_name);

    return $st_handle->rows > 0 ? $st_handle->fetchrow_array() : undef;
}


sub get_BIDSExportFileLevelCategoryID {
    my ($level_name) = @_;

    (my $get_query = <<QUERY ) =~ s/\n/ /g;
SELECT BIDSExportFileLevelCategoryID
FROM bids_export_file_level_category
WHERE BIDSExportFileLevelCategoryName = ?
QUERY

    my $st_handle = $dbh->prepare($get_query);
    $st_handle->execute($level_name);
    return $st_handle->fetchrow_array() if $st_handle->rows > 0;

    # need to create the file level into the file level table since could not find it
    my $insert_q = "INSERT bids_export_file_level_category SET BIDSExportFileLevelCategoryName = ?";
    $st_handle = $dbh->prepare($insert_q);
    $st_handle->execute($level_name);

    $st_handle = $dbh->prepare($get_query);
    $st_handle->execute($level_name);

    return $st_handle->fetchrow_array();
}

__END__
=pod

=head1 TO DO

    - Make the SliceOrder, which is currently an argument at the command line,
    more robust (such as making it adaptable across manufacturers that might not
    have this header present in the DICOMs, not just Philips like is currently the
    case in this script. In addition, this variable can/should be defined on a site
    per site basis.
    - Need to add to the multi-echo sequences a JSON file with the echo time within,
    as well as the originator NIfTI parent file. In addition, we need to check from
    the database if the sequence is indeed a multi-echo and require the
    C<BIDSMultiEcho> column set by the project in the C<bids_mri_scan_type_rel>
    table.


=head1 COPYRIGHT AND LICENSE

License: GPLv3


=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut
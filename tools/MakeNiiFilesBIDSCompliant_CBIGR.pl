#! /usr/bin/perl

=pod

=head1 NAME

MakeNIIFilesBIDSCompliant.pl -- a script that creates a BIDS compliant imaging
dataset from the MINCs in the C<assembly/> directory

=head1 SYNOPSIS

perl tools/MakeNIIFilesBIDSCompliant.pl C<[options]>

Available options are:

-profile                : name of the config file in C<../dicom-archive/.loris_mri>

-tarchive_id            : The ID of the DICOM archive to be converted into BIDS
                        dataset (optional, if not set, convert all DICOM archives)

-dataset_name           : Name/Description of the dataset about to be generated
                        in BIDS format; for example BIDS_First_Sample_Data. The
                        BIDS data will be stored in a directory called the C<dataset_name>

-slice_order_philips    : Philips scanners do not have the C<SliceOrder> in their
                        DICOMs so provide it as an argument; C<ascending> or
                        C<descending> is expected; otherwise, it will be logged
                        in the JSON as C<Not Supplied>"

-verbose                : if set, be verbose


=head1 DESCRIPTION

This **BETA** version script will create a BIDS compliant NIfTI file structure of
the MINC files currently present in the C<assembly> directory. If the argument
C<tarchive_id> is specified, only the images from that archive will be
processed. Otherwise, all files in C<assembly> will be included in the BIDS
structure, while looping though all the C<tarchive_id>'s in the C<tarchive>
table.

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
Run C<sudo apt-get install libjson-perl> to get it.

=head2 Methods

=cut

use strict;
use warnings;
use Getopt::Tabular;
use File::Path qw/ make_path /;
use File::Basename;
use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::ExitCodes;
use JSON;

my $AUTHORS = [
    'The Montreal Neurological Institute and Hospital'
];
my $ACKNOWLEDGMENTS = <<TEXT;
TEXT
my $README = <<TEXT;
The Neuro’s C-BIG Repository is an Open Science collection of biological samples,
clinical information, imaging, and genetic data from patients with neurological
disease as well as from healthy control subjects.

Data and samples collected in the C-BIG Repository will be made available to
research teams with scientifically and ethically valid proposals around the world,
congruent with Open Science principles.

This BIDS dataset is the collection of images present in the C-BIG Repository.

For support, please contact cbig_support.mni\@mcgill.ca. More details can also be found at:

- https://cbigr-open.loris.ca
- https://www.mcgill.ca/neuro/open-science
TEXT
my $BIDS_VALIDATOR_CONFIG = <<TEXT;
{
  "ignore": [1, 11, 29, 41, 102]
}
TEXT


my $profile             = undef;
my $tarchiveID          = undef;
my $BIDSVersion         = "1.1.1 & BEP0001";
my $LORISScriptVersion  = "0.1"; # Still a BETA version
my $datasetName         = undef;
my $sliceOrderPhilips   = "Not Supplied";
my $verbose             = 0;

my @opt_table = (
    [ "-profile", "string", 1, \$profile,
      "name of config file in ../dicom-archive/.loris_mri"
    ],
    [ "-tarchive_id", "string", 1, \$tarchiveID,
      "tarchive_id of the .tar to be processed from tarchive table"
    ],
    [ "-dataset_name", "string", 1, \$datasetName,
      "Name/Description of the dataset about to be generated in BIDS format; for example BIDS_First_Sample_Data"
    ],
    [ "-slice_order_philips", "string", 1, \$sliceOrderPhilips,
            "Philips scanners do not have the SliceOrder in their DICOMs so
            provide it as an argument; 'ascending' or 'descending' is expected;
            otherwise, it will be logged in the JSON as 'Not Supplied'"
    ],
    ["-verbose", "boolean", 1,   \$verbose, "Be verbose."]
);

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

&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;
################################################################
############### input option error checking ####################
################################################################

if ( !$profile ) {
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

if ( !$datasetName ) {
    print $Help;
    print "$Usage\n\tERROR: The dataset name needs to be provided. "
        . "It is required by the BIDS specifications to populate the "
        . "dataset_description.json file \n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}


# Establish database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\n==> Successfully connected to database \n";

# This setting is in the ConfigSettings table
my $dataDir = &NeuroDB::DBI::getConfigSetting(\$dbh,'dataDirBasepath');
my $binDir  = &NeuroDB::DBI::getConfigSetting(\$dbh,'MRICodePath');
my $prefix  = &NeuroDB::DBI::getConfigSetting(\$dbh,'prefix');

$dataDir =~ s/\/$//g;
$binDir  =~ s/\/$//g;

# Make destination directory for the NIfTI files
# same level as assembly/ directory but named as BIDS_export/
my $destDir = $dataDir . "/BIDS_export";
make_path($destDir) unless(-d $destDir);
# Append to the destination directory name
$destDir = $destDir . "/" . $datasetName;
if (-d  $destDir) {
    print "\n*******Directory $destDir already exists, APPENDING new candidates ".
        "and OVERWRITING EXISTING ONES*******\n";
}
else {
    make_path($destDir);
}

# Get the LORIS-MRI version number from the VERSION file
my $MRIVersion;
my $versionFile = $binDir . '/VERSION';
open(my $fh, '<', $versionFile) or die "cannot open file $versionFile";
{
    local $/;
    $MRIVersion = <$fh>;
    $MRIVersion =~ s/\n//g;
}
close($fh);

# Create the dataset_description.json file
my $dataDescFileName = "dataset_description.json";
my $dataDescFile     = $destDir . "/" . $dataDescFileName;
print "\n*******Creating the dataset description file $dataDescFile *******\n";
my %dataset_desc_hash = (
    'BIDSVersion'           => $BIDSVersion,
    'Name'                  => $datasetName,
    'LORISScriptVersion'    => $LORISScriptVersion,
    'Authors'               => $AUTHORS,
    'HowToAcknowledge'      => $ACKNOWLEDGMENTS,
    'LORISReleaseVersion'   => $MRIVersion
);
unless (-e $dataDescFile) {
    write_BIDS_JSON_file($dataDescFile, \%dataset_desc_hash);
    registerBidsFileInDatabase(
        $dataDescFile, 'study',               'json', undef,
        undef,         'dataset_description', undef
    );
}

# Create the README BIDS file
my $readmeFile = $destDir . "/README";
print "\n*******Creating the README file $readmeFile *******\n";
unless (-e $readmeFile) {
    open README, ">$readmeFile" or die "Can not write file $readmeFile: $!\n";
    README->autoflush(1);
    select(README);
    select(STDOUT);
    print README "$README\n";
    close README;
    registerBidsFileInDatabase(
        $readmeFile, 'study',  'README', undef,
        undef,       'README', undef
    );
}

# Create a .gitignore file for BIDS validator to ignore file types that are not
# yet part of the BIDS specification
my $bids_validator_config_file = $destDir . "/.bids-validator-config.json";
print "\n*******Creating the .bids-validator-config.json file $bids_validator_config_file *******\n";
unless (-e $bids_validator_config_file) {
    open BIDSIGNORE, ">$bids_validator_config_file"
        or die "Can not write file $bids_validator_config_file: $!\n";
    BIDSIGNORE->autoflush(1);
    select(BIDSIGNORE);
    select(STDOUT);
    print BIDSIGNORE "$BIDS_VALIDATOR_CONFIG\n";
    close BIDSIGNORE;
    registerBidsFileInDatabase(
        $bids_validator_config_file, 'study',                 'json', undef,
        undef,                       'bids-validator-config', undef
    );
}



my ($query, $sth);

# Query to grep all distinct TarchiveIDs from the database 
if (!defined($tarchiveID)) {
    ( $query = <<QUERY ) =~ s/\n/ /g;
SELECT DISTINCT
  TarchiveID
FROM
  tarchive
QUERY
    # Prepare and execute query
    $sth = $dbh->prepare($query);
    $sth->execute();
}
else{
    ( $query = <<QUERY ) =~ s/\n/ /g;
SELECT DISTINCT
  TarchiveID
FROM
  tarchive
WHERE
  TarchiveID = ?
QUERY
    # Prepare and execute query
    $sth = $dbh->prepare($query);
    $sth->execute($tarchiveID);
}
while ( my $rowhr = $sth->fetchrow_hashref()) {
    my $givenTarchiveID = $rowhr->{'TarchiveID'};
    print "\n*******Currently creating a BIDS directory of NIfTI files for ".
            "TarchiveID $givenTarchiveID********\n";

    # Grep files list in a hash
    # If no TarchiveID is given loop through all
    # Else, use the given TarchiveID at the command line

    my %file_list = &getFileList( $dbh, $givenTarchiveID );
    # needed to clean up the list of files since phase and mag have same scan types
    my %filtered_file_list = &cleanup_list_files_from_CBIGR(%file_list);

    # Make NIfTI files and JSON headers out of those MINC
    my $phasediff_list = &makeNIIAndHeader( $dbh, %filtered_file_list);

    # update the IntendedFor field for fieldmap phasediff JSON files
    &updateFieldmapIntendedFor(\%filtered_file_list, $phasediff_list);

    # update the IntendedFor field for T1 JSON file based on when
    # SCOUTs were acquired in the tarchive_series table
    # not necessary for CBIGR
    #&updateT1IntendedFor($dbh, \%filtered_file_list, $givenTarchiveID);

    if (defined($tarchiveID)) {
        print "\nFinished processing TarchiveID $givenTarchiveID\n";
    }
}

if (!defined($tarchiveID)) {
    print "\nFinished processing all tarchives\n";
}
$dbh->disconnect();
exit $NeuroDB::ExitCodes::SUCCESS;


=pod

=head3 getFileList($dbh, $givenTarchiveID)

This function will grep all the C<TarchiveID> and associated C<ArchiveLocation>
present in the C<tarchive> table and will create a hash of this information
including new C<ArchiveLocation> to be inserted into the database.

INPUTS:
    - $dbh             : database handler
    - $givenTarchiveID : the C<TarchiveID> under consideration

RETURNS:
    - %file_list       : hash with files for a given C<TarchiveID>

=cut

sub getFileList {

    my ($dbh, $givenTarchiveID) = @_;

    # Query to grep all file entries
    ### NOTE: parameter type hardcoded for open prevent ad...
    ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  f.FileID,
  File,
  AcquisitionProtocolID,
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

LEFT JOIN parameter_file pf_echonb    ON (f.FileID=pf_echonb.FileID)    AND pf_echonb.ParameterTypeID    = 1293
LEFT JOIN parameter_file pf_seriesnb  ON (f.FileID=pf_seriesnb.FileID)  AND pf_seriesnb.ParameterTypeID  = 1734
LEFT JOIN parameter_file pf_imagetype ON (f.FileID=pf_imagetype.FileID) AND pf_imagetype.ParameterTypeID = 2082

WHERE f.OutputType IN ('native', 'defaced')
AND f.FileType       = 'mnc'
AND c.Entity_type    = 'Human'
AND t.TarchiveID = ?
QUERY

    # Prepare and execute query
    my $sth = $dbh->prepare($query);
    $sth->execute($givenTarchiveID);
    
    # Create file list hash with ID and relative location
    my %file_list;
    my $i = 0;
    
    while ( my $rowhr = $sth->fetchrow_hashref()) {
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

=head3 cleanup_list_files_from_CBIGR(%file_list)

=cut

sub cleanup_list_files_from_CBIGR {
    my (%file_list) = @_;

    # this is the list of scan types to ignore when converting to BIDS
    # a.k.a. anatomical scans that are not defaced, T1WNeuromel...
    my @scan_types_to_ignore = (
        '3DT1',                                   '2DFLAIRFS',
        'PDT2TE1',                                'PDT2TE2',
        'BOLDRSgrefieldmappingTE1',               'BOLDRSgrefieldmappingTE2-defaced',
        'T1WNeuromelTR6001.8mmTE10FA120BW1807av'
    );

    my %image_type_file_per_scan_type = (
        'T2star'         => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'T2star-defaced' => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'BOLDRSgrefieldmappingTE2'         => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'BOLDRSgrefieldmappingTE1-defaced' => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND\\\\NORM',
        'GRE10echosDrCollinsTE1'           => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE1-defaced'   => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'GRE10echosDrCollinsTE2'           => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE2-defaced'   => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'GRE10echosDrCollinsTE3'           => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE3-defaced'   => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'GRE10echosDrCollinsTE4'           => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE4-defaced'   => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'GRE10echosDrCollinsTE5'           => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE5-defaced'   => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'GRE10echosDrCollinsTE6'           => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE6-defaced'   => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'GRE10echosDrCollinsTE7'           => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE7-defaced'   => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'GRE10echosDrCollinsTE8'           => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE8-defaced'   => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'GRE10echosDrCollinsTE9'           => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE9-defaced'   => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND',
        'GRE10echosDrCollinsTE10'          => 'ORIGINAL\\\\PRIMARY\\\\P\\\\ND',
        'GRE10echosDrCollinsTE10-defaced'  => 'ORIGINAL\\\\PRIMARY\\\\M\\\\ND'
    );

    my @keys_to_remove = [];
    for my $row (keys %file_list) {
        my $scan_type  = $file_list{$row}{'lorisScanType'};
        my $image_type = $file_list{$row}{'imageType'};

        # if scan type in scan types to ignore, add this row to the list of files to remove from  %file_list
        push (@keys_to_remove, $row) if grep (/^$scan_type$/, @scan_types_to_ignore);

        for my $scan_type_entry (keys %image_type_file_per_scan_type) {
            if ($scan_type_entry eq $scan_type) {
                push (@keys_to_remove,
                    $row) unless $image_type eq $image_type_file_per_scan_type{$scan_type_entry};
            }
        }
    }

    for my $key (@keys_to_remove) {
        delete $file_list{$key};
    }

    determine_run_number(%file_list);

    return %file_list;
}


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
        # note: T2star and Collins acquisition have the same scan type
        # for the phase and the magnitude image, hence the different
        # calculation for the run number
        if ($scan_type =~ /^(GRE10echosDrCollins)|(T2star)/) {
            my $i = 1;
            for my $row (@sorted_list_of_scans) {
                my $hash_id = $row->{'hash_id'};
                $file_list{$hash_id}{'run_number'} = "00" . int($i);
                $i += 0.5;
            }
        } else {
            my $i = 1;
            for my $row (@sorted_list_of_scans) {
                my $hash_id = $row->{'hash_id'};
                $file_list{$hash_id}{'run_number'} = "00$i";
                $i++;
            }
        }
    }
}


=pod

=head3 makeNIIAndHeader($dbh, %file_list)

This function will make NIfTI files out of the MINC files and puts them in BIDS
format.
It also creates a .json file for each NIfTI file by getting the header values
from the C<parameter_file> table. Header information is selected based on the
BIDS document
(L<BIDS specifications|http://bids.neuroimaging.io/bids_spec1.0.2.pdf>; page
14 through 17).

INPUTS:
    - $dbh          : database handler
    - $file_list    : hash with files' information.

=cut

sub makeNIIAndHeader {
    
    my ( $dbh, %file_list) = @_;

    my %phasediff_seriesnb_hash;
    foreach my $row (keys %file_list) {
        my $fileID         = $file_list{$row}{'fileID'};
        my $minc           = $file_list{$row}{'file'};
        my $acqProtocolID  = $file_list{$row}{'AcquisitionProtocolID'};
        my $sessionID      = $file_list{$row}{'sessionID'};

        ### check if the MINC file can be found on the file system
        my $minc_full_path = "$dataDir/$minc";
        if (! -e $minc_full_path) {
            print "\nCould not find the following MINC file: $minc_full_path\n"
                if $verbose;
            next;
        }

        ### Get the BIDS scans label information
        my ($bids_categories_hash) = grep_bids_scan_categories_from_db($dbh, $acqProtocolID);
        unless ($bids_categories_hash) {
            print "$minc will not be converted into BIDS as no entries were found "
                  . "in the bids_mri_scan_type_rel table for that scan type.\n";
            next;
        }
        $file_list{$row}{'BIDSScanType'}     = $bids_categories_hash->{'BIDSScanType'};
        $file_list{$row}{'BIDSCategoryName'} = $bids_categories_hash->{'BIDSCategoryName'};


        ### skip if BIDS scan type contains magnitude since they will be created
        ### when taking care of the phasediff fieldmap
        my $bids_scan_type   = $bids_categories_hash->{'BIDSScanType'};
        next if $bids_scan_type =~ m/magnitude/g;

        ### create an entry in participants.tsv file if it was not already created
        add_entry_in_participants_bids_file($file_list{$row}, $destDir, $dbh);

        ### determine the BIDS NIfTI filename
        my $niftiFileName = determine_bids_nifti_file_name(
            $minc, $prefix, $file_list{$row}, $bids_categories_hash, $file_list{$row}{'run_number'}
        );

        ### create the BIDS directory where the NIfTI file would go
        my $bids_scan_directory = determine_BIDS_scan_directory(
            $file_list{$row}, $bids_categories_hash, $destDir
        );
        make_path($bids_scan_directory) unless(-d  $bids_scan_directory);

        ### Convert the MINC file into the BIDS NIfTI file
        print "\n*******Currently processing $minc_full_path********\n";
        #  mnc2nii command then gzip it because BIDS expects it this way
        my $success = create_nifti_bids_file(
            $dataDir, $minc, $bids_scan_directory, $niftiFileName, $fileID
        );
        unless ($success) {
            print "WARNING: mnc2nii conversion failed for $minc.\n";
            next;
        }

        # determine JSON filename
        my ($json_filename, $json_fullpath) = determine_BIDS_scan_JSON_file_path(
            $niftiFileName, $bids_scan_directory
        );
        $file_list{$row}{'niiFileName'}  = "$niftiFileName.gz";
        $file_list{$row}{'niiFilePath'}  = "$bids_scan_directory/$niftiFileName.gz";
        $file_list{$row}{'jsonFilePath'} = $json_fullpath;

        #  determine JSON information from MINC files header;
        my ($header_hash) = gather_parameters_for_BIDS_JSON_file(
            $minc_full_path, $json_filename, $bids_categories_hash
        );

        # for phasediff files, replace EchoTime by EchoTime1 and EchoTime2
        # and create the magnitude files associated with it
        if ($bids_scan_type =~ m/phasediff/i) {
            #### hardcoded for open PREVENT-AD since always the same for
            #### all datasets...
            my $series_number = $file_list{$row}{'seriesNumber'};
            $phasediff_seriesnb_hash{$series_number}{'jsonFilePath'} = $json_fullpath;
            delete($header_hash->{'EchoTime'});
            $header_hash->{'EchoTime1'} = 0.00492;
            $header_hash->{'EchoTime2'} = 0.00738;
            my ($magnitude_files_hash) = grep_phasediff_associated_magnitude_files(
                \%file_list, $file_list{$row}, $dbh
            );
            create_BIDS_magnitude_files($niftiFileName, $magnitude_files_hash);
        }

        if ( $bids_categories_hash->{'BIDSScanTypeSubCategory'}
             && $bids_categories_hash->{'BIDSScanTypeSubCategory'} =~ m/task-(encoding|retrieval)/i) {
            my $task_type = $1;
            makeTaskTextFiles($dbh, $sessionID, $task_type, "$bids_scan_directory/$niftiFileName");
        }

        unless (-e $json_fullpath) {
            write_BIDS_JSON_file($json_fullpath, $header_hash);
            my $modalitytype = $bids_categories_hash->{'BIDSCategoryName'};
            registerBidsFileInDatabase(
                $json_fullpath, 'image', 'json',     $fileID,
                $modalitytype,  undef,   undef
            );
        }

        # DWI files need 2 extra special files; .bval and .bvec
        if ($bids_scan_type eq 'dwi') {
            create_DWI_bval_bvec_files($dbh, $niftiFileName, $fileID, $bids_scan_directory);
        }

        ### add an entry in the sub-xxx_scans.tsv file with age
        my $nifti_full_path = "$bids_scan_directory/$niftiFileName";
        add_entry_in_scans_tsv_bids_file($file_list{$row}, $destDir, $nifti_full_path, $sessionID, $dbh);
    }

    return \%phasediff_seriesnb_hash;
}

=pod

=head3 fetchBVAL_BVEC($dbh, $bvFile, $fileID, $destDirFinal, @headerNameBVECDBArr)

This function will create C<bval> and C<bvec> files from a DWI input file, in a
BIDS compliant manner. The values (bval OR bvec) will be fetched from the
database C<parameter_file> table.

INPUTS:
    - $dbh                  : database handler
    - $bvfile               : bval or bvec filename
    - $nifti                : original NIfTI file
    - $fileID               : ID of the file from the C<files> table
    - $destDirFinal         : final directory destination for the file to be
                              generated
    - @headerNameBVECDBArr  : array for the names of the database parameter to
                              be fetched (bvalues for bval and x, y, z direction
                              for bvec)

=cut

sub fetchBVAL_BVEC {
    my ( $dbh, $nifti, $bvFile, $filetype, $fileID, $destDirFinal, @headerNameBVDBArr) = @_;

    return if -e "$destDirFinal/$bvFile";

    my ( $headerName, $headerNameDB, $headerVal);

    open BVINFO, ">$destDirFinal/$bvFile";
    BVINFO->autoflush(1);
    select(BVINFO);
    select(STDOUT);

    foreach my $j (0..scalar(@headerNameBVDBArr)-1) {
        $headerNameDB = $headerNameBVDBArr[$j];
        $headerNameDB =~ s/^\"+|\"$//g;
        print "Adding now $headerName header to $bvFile\n" if $verbose;;
        ( $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  pf.Value
FROM
  parameter_file pf
JOIN
  files f
ON
  pf.FileID=f.FileID
WHERE
  pf.ParameterTypeID = (SELECT pt.ParameterTypeID from parameter_type pt WHERE pt.Name = ?)
AND
  f.FileID = ?
QUERY
        # Prepare and execute query
        $sth = $dbh->prepare($query);
        $sth->execute($headerNameDB,$fileID);
        if ( $sth->rows > 0 ) {
            $headerVal = $sth->fetchrow_array();
            $headerVal =~ s/\.\,//g;
            $headerVal =~ s/\,//g;
            # There is one last trailing . usually in bval; remove it
            $headerVal =~ s/\.$//g;
            print BVINFO "$headerVal \n";
            print "     $headerNameDB was found for $nifti with value
            $headerVal\n" if $verbose;;
        }
        else {
            print "     $headerNameDB was not found for $nifti\n" if $verbose;
        }
    }

    close BVINFO;

    registerBidsFileInDatabase(
        "$destDirFinal/$bvFile", 'image', $filetype, $fileID,
        'dwi',                   undef,   undef
    );
}


sub grep_bids_scan_categories_from_db {
    my ($dbh, $acqProtocolID) = @_;

    # Get the scan category (anat, func, dwi, to know which subdirectory to place files in
    ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  bmstr.MRIScanTypeID,
  bids_category.BIDSCategoryName,
  bids_scan_type_subcategory.BIDSScanTypeSubCategory,
  bids_scan_type.BIDSScanType,
  bmstr.BIDSEchoNumber,
  mst.Scan_type

FROM bids_mri_scan_type_rel bmstr
  JOIN      mri_scan_type mst          ON mst.ID = bmstr.MRIScanTypeID
  JOIN      bids_category              USING (BIDSCategoryID)
  JOIN      bids_scan_type             USING (BIDSScanTypeID)
  LEFT JOIN bids_scan_type_subcategory USING (BIDSScanTypeSubCategoryID)

WHERE
  mst.ID = ?
QUERY
    # Prepare and execute query
    my $sth = $dbh->prepare($query);
    $sth->execute($acqProtocolID);
    my $rowhr = $sth->fetchrow_hashref();

    return $rowhr;
}

sub create_nifti_bids_file {
    my ($data_dir, $minc_path, $bids_dir, $nifti_name, $fileID, $modality_type) = @_;

    return 1 if -e "$bids_dir/$nifti_name.gz";

    my $cmd = "mnc2nii -nii -quiet $data_dir/$minc_path $bids_dir/$nifti_name";
    system($cmd);

    my $gz_cmd = "gzip -f $bids_dir/$nifti_name";
    system($gz_cmd);

    registerBidsFileInDatabase(
        "$bids_dir/$nifti_name.gz", 'image', 'nii', $fileID,
        $modality_type,             undef,   undef
    );

    return -e "$bids_dir/$nifti_name.gz";
}

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
    # sequences with multi-echo need to have echo-1. echo-2, etc... appended to the filename
    # TODO: add a check if the sequence is indeed a multi-echo (check SeriesUID
    # and EchoTime from the database), and if not set, issue an error
    # and exit and ask the project to set the BIDSMultiEcho for these sequences
    # Also need to add .JSON for those multi-echo files
    if ($bids_echo_nb) {
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

    # make the filename have the BIDS Scan type name, in case the project
    # Scan type name is not compliant;
    # and append the word 'run' before run number
    # If the file is of type fMRI; need to add a BIDS subcategory type
    # for example, task-rest for resting state fMRI
    # or task-memory for memory task fMRI
    # Exclude ASL as these are under 'func' for BIDS but will not have BIDSScanTypeSubCategory
    if ($bids_category eq 'func' && $bids_scan_type !~ m/asl/i) {
        if ($bids_label_hash->{BIDSScanTypeSubCategory}) {
            $replace = $bids_subcategory . "_run-";
        } else {
            print STDERR "\n ERROR: Files of BIDS Category type 'func' and
                                 which are fMRI need to have their
                                 BIDSScanTypeSubCategory defined. \n\n";
            exit $NeuroDB::ExitCodes::PROJECT_CUSTOMIZATION_FAILURE;
        }
    } elsif ($bids_scan_type eq 'dwi') {
        if ($bids_label_hash->{BIDSScanTypeSubCategory}) {
            $replace = $bids_subcategory . "_run-";
        } else {
            $replace = "run-";
        }
    } elsif ($bids_scan_type eq 'T2star') {
        if ($bids_label_hash->{BIDSScanTypeSubCategory}) {
            $replace = $bids_subcategory . "_run-";
        } else {
            print STDERR "\n ERROR: Files of BIDS Scan type 'T2star' with multiple echoes
                                need to have their BIDSScanTypeSubCategory defined. \n\n";
            exit $NeuroDB::ExitCodes::PROJECT_CUSTOMIZATION_FAILURE;
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
        if ($echo_nb) {
            $bids_scan_type .= $echo_nb;
        }
    } elsif ($run_nb) {
        $nifti_name =~ s/run-\d\d\d/run-$run_nb/g;
    }

    # find position of the last dot of the NIfTI file, where the extension starts
    my ($base, $path, $ext) = fileparse($nifti_name, qr{\..*});
    $nifti_name = $base . "_" . $bids_scan_type . $ext;

    return $nifti_name;
}

sub add_entry_in_participants_bids_file {
    my ($minc_file_hash, $bids_root_dir, $dbh) = @_;

    my $participants_tsv_file  = $bids_root_dir . '/participants.tsv';
    my $participants_json_file = $bids_root_dir . '/participants.json';

    my $candID = $minc_file_hash->{'candID'};

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
            return if ($row =~ m/^sub-$candID/);
        }
    }

    # grep the values to insert in the participants.tsv file
    my $values = grep_participants_values_from_db($dbh, $candID);
    open (FH, '>>:encoding(utf8)', $participants_tsv_file) or die " $!";
    print FH (join("\t", @$_), "\n") for $values;
    close FH;
}

sub grep_participants_values_from_db {
    my ($dbh, $candID) = @_;

    ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  Sex
FROM
  candidate
WHERE
  CandID = ?;
QUERY

    my $sth = $dbh->prepare($query);
    $sth->execute($candID);

    my @values = $sth->fetchrow_array;
    unshift(@values, "sub-$candID");

    return \@values;
}

sub create_participants_tsv_and_json_file {
    my ($participants_tsv_file, $participants_json_file) = @_;

    # create participants.tsv file
    my @header_row = [
        'participant_id', 'sex'
    ];
    open(FH, ">:encoding(utf8)", $participants_tsv_file) or die " $!";
    print FH (join("\t", @$_), "\n") for @header_row;
    close FH;

    # create participants.json file
    my %header_dict = (
        'sex' => {
            'Description' => 'sex of the participant',
            'Levels'      => {'Male' => 'Male', 'Female' => 'Female'}
        }
    );
    write_BIDS_JSON_file($participants_json_file, \%header_dict);
}

sub add_entry_in_scans_tsv_bids_file {
    my ($minc_file_hash, $bids_root_dir, $nifti_full_path, $sessionID, $dbh) = @_;

    my $bids_sub_id = "sub-$minc_file_hash->{'candID'}";
    my $bids_ses_id = "ses-$minc_file_hash->{'visitLabel'}";

    my $bids_scans_rootdir   = "$bids_root_dir/$bids_sub_id/$bids_ses_id";
    my $bids_scans_tsv_file  = "$bids_scans_rootdir/$bids_sub_id\_$bids_ses_id\_scans.tsv";
    my $bids_scans_json_file = "$bids_scans_rootdir/$bids_sub_id\_$bids_ses_id\_scans.json";

    # determine the filename entry to be added to the TSV file
    my $filename_entry = "$nifti_full_path.gz";
    $filename_entry =~ s/$bids_scans_rootdir\///g;

    if (! -e $bids_scans_tsv_file) {
        # create the tsv and json file if they do not exist
        create_scans_tsv_and_json_file($bids_scans_tsv_file, $bids_scans_json_file);
        registerBidsFileInDatabase(
            $bids_scans_tsv_file, 'session',               'tsv',     undef,
            undef,                'session_list_of_scans', $sessionID
        );
        registerBidsFileInDatabase(
            $bids_scans_json_file, 'session',               'json',    undef,
            undef,                 'session_list_of_scans', $sessionID
        );
    } else {
        # read participants.tsv file and check if a row is already present for
        # that subject
        open (FH, '<:encoding(utf8)', $bids_scans_tsv_file) or die " $!";
        while (my $row = <FH>) {
            return if ($row =~ m/^$filename_entry/);
        }
    }

    # grep the values to insert in the participants.tsv file
    my $candID     = $minc_file_hash->{'candID'};
    my $visitLabel = $minc_file_hash->{'visitLabel'};
    my $values     = grep_age_values_from_db($dbh, $candID, $visitLabel, $filename_entry);
    open (FH, '>>:encoding(utf8)', $bids_scans_tsv_file) or die " $!";
    print FH (join("\t", @$_), "\n") for $values;
    close FH;
}

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

sub grep_age_values_from_db {
    my ($dbh, $candID, $visitLabel, $filename_entry) = @_;

    ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  TIMESTAMPDIFF(MONTH, DoB, Date_visit)
FROM
  candidate
  JOIN session USING (CandID)
WHERE
  CandID = ? AND Visit_label = ?;
QUERY

    my $sth = $dbh->prepare($query);
    $sth->execute($candID, $visitLabel);

    my @values = $sth->fetchrow_array;
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


sub determine_BIDS_scan_JSON_file_path {
    my ($nifti_name, $bids_scan_directory) = @_;

    my $json_filename = $nifti_name;
    $json_filename    =~ s/nii/json/g;

    my $json_fullpath = "$bids_scan_directory/$json_filename";

    return ($json_filename, $json_fullpath);
}


sub write_BIDS_JSON_file {
    my ($json_fullpath, $header_hash) = @_;

    my $json = JSON->new->allow_nonref;
    my $currentHeaderJSON = $json->pretty->encode($header_hash);

    open HEADERINFO, ">$json_fullpath" or die "Can not write file $json_fullpath: $!\n";
    HEADERINFO->autoflush(1);
    select(HEADERINFO);
    select(STDOUT);
    print HEADERINFO "$currentHeaderJSON";
    close HEADERINFO;
}

sub create_DWI_bval_bvec_files {
    my ($dbh, $nifti_file_name, $fileID, $bids_scan_directory) = @_;

    my @headerNameBVALDBArr = ("acquisition:bvalues");
    my @headerNameBVECDBArr = ("acquisition:direction_x","acquisition:direction_y","acquisition:direction_z");

    #BVAL first
    my $bvalFile = $nifti_file_name;
    $bvalFile    =~ s/nii/bval/g;
    &fetchBVAL_BVEC(
        $dbh,    $nifti_file_name,     $bvalFile,            'bval',
        $fileID, $bids_scan_directory, @headerNameBVALDBArr
    );

    #BVEC next
    my $bvecFile = $nifti_file_name;
    $bvecFile    =~ s/nii/bvec/g;
    &fetchBVAL_BVEC(
        $dbh,    $nifti_file_name,     $bvecFile,            'bvec',
        $fileID, $bids_scan_directory, @headerNameBVECDBArr
    );
}

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
        add_PhaseEncodingDirection_info_for_JSON_file($header_hash);
        add_EffectiveEchoSpacing_and_TotalReadoutTime_info_for_JSON_file($header_hash, $minc_full_path);
    }

    # for MP2RAGE, we need to add RepetitionTimeExcitation
    if ($bids_scan_type eq 'MP2RAGE' || $bids_scan_type eq 'T1map' || $bids_scan_type eq 'UNIT1') {
        add_RepetitionTimeExcitation_info_for_JSON_file($header_hash, $minc_full_path);
    }

    # for ASL, we need to add a few fields to the JSON file (note they are hardcoded
    # as could not find them in the MINC header)
    if ($bids_scan_type eq 'asl') {
        add_ASL_specific_info_for_JSON_file($header_hash);
    }

    return $header_hash;
}

sub grep_generic_header_info_for_JSON_file {
    my ($minc_full_path, $json_filename) = @_;

    # get this info from the MINC header instead of the database
    # Name is as it appears in the database
    # slice order is needed for resting state fMRI
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
        print "Adding now $bids_header_name header to info to write to $json_filename\n" if $verbose;

        my $header_value = NeuroDB::MRI::fetch_header_info(
            $minc_full_path, $minc_header_name
        );

        # Some headers need to be explicitly converted to floats in Perl
        # so json_encode does not add the double quotation around them
        my @convertToFloat = [
            'acquisition:repetition_time',     'acquisition:echo_time',
            'acquisition:inversion_time',      'dicom_0x0018:el_0x1314',
            'acquisition:imaging_frequency',   'study:field_value',
            'dicom_0x0020:el_0x0011',          'dicom_0x0020:el_0x0012',
            'acquisition:slice_thickness',     'acquisition:SAR',
            'dicom_0x0018:el_0x1314',          'acquisition:percent_phase_fov',
            'acquisition:num_phase_enc_steps', 'acquisition:pixel_bandwidth',
            'acquisition:echo_number'
        ];
        $header_value *= 1 if ($header_value && $minc_header_name ~~ @convertToFloat);
        $header_value /= 1000000 if ($header_value && $minc_header_name eq 'acquisition:imaging_frequency');
        my @convertToArray = ['acquisition:image_type', 'dicom_0x0020:el_0x0037'];
        if ($header_value && $minc_header_name ~~ @convertToArray) {
            my @values = split("\\\\\\\\", $header_value);
            $header_value = \@values;
        }

        if (defined($header_value)) {
            $header_hash{$bids_header_name} = $header_value;
            print "     $bids_header_name was found for $minc_full_path with value $header_value\n" if $verbose;

            # If scanner is Philips, store this as condition 1 being met
            if ($minc_header_name eq 'study:manufacturer' && $header_value =~ /Philips/i) {
                $manufacturerPhilips = 1;
            }
        }
        else {
            print "     $bids_header_name was not found for $minc_full_path\n" if $verbose;
        }
    }

    grep_SliceOrder_info_for_JSON_file(\%header_hash, $minc_full_path, $manufacturerPhilips);

    return (\%header_hash);
}

sub add_PhaseEncodingDirection_info_for_JSON_file {
    my ($header_hash) = @_;

    ### Note: this is hardcoded as this information is not available in the MINC
    ### files and is stable across the PREVENT-AD project.
    $header_hash->{'PhaseEncodingDirection'} = 'j-';
}

sub add_EffectiveEchoSpacing_and_TotalReadoutTime_info_for_JSON_file {
    my ($header_hash, $minc_full_path) = @_;

    # Conveniently, for Siemens’ data, this value is easily obtained as
    # 1/[BWPPPE * ReconMatrixPE], where BWPPPE is the "BandwidthPerPixelPhaseEncode
    # in DICOM tag (0019,1028) and ReconMatrixPE is the size of the actual
    # reconstructed data in the phase direction (which is NOT reflected in a
    # single DICOM tag for all possible aforementioned scan manipulations)
    my $bwpppe = &NeuroDB::MRI::fetch_header_info(
        $minc_full_path, 'dicom_0x0019:el_0x1028'
    );
    my $reconMatrixPE = &NeuroDB::MRI::fetch_header_info(
        $minc_full_path, 'dicom_0x0051:el_0x100b'
    );
    $reconMatrixPE =~ s/[a-z]?\*\d+[a-z]?//;

    # compute the effective echo spacing
    my $effectiveEchoSpacing =  1 / ($bwpppe * $reconMatrixPE);
    $header_hash->{'EffectiveEchoSpacing'} = $effectiveEchoSpacing;

    # compute the total readout time
    # If EffectiveEchoSpacing has been properly computed, TotalReadoutTime is just
    # EffectiveEchoSpacing * (ReconMatrixPE - 1)
    $header_hash->{'TotalReadoutTime'} = $effectiveEchoSpacing * ($reconMatrixPE - 1)
}

sub add_RepetitionTimeExcitation_info_for_JSON_file {
    my ($header_hash, $minc_full_path) = @_;

    # RepetitionTimeExcitation is stored in DICOM field dicom_0x0018:el_0x0080
    my $reptimeexcitation = &NeuroDB::MRI::fetch_header_info(
        $minc_full_path, 'dicom_0x0018:el_0x0080'
    );

    $header_hash->{'RepetitionTimeExcitation'} = $reptimeexcitation / 1000;
}

sub add_ASL_specific_info_for_JSON_file {
    my ($header_hash) = @_;

    # these are all hardcoded as they cannot be found in the MINC file
    $header_hash->{'LabelingType'}          = 'PCASL';
    $header_hash->{'ASLContext'}            = '(Label-Control)*40';
    $header_hash->{'LabelingDuration'}      = 1.5;
    $header_hash->{'InitialPostLabelDelay'} = 0.9;
    $header_hash->{'BackgroundSuppression'} = 'False';
    $header_hash->{'VascularCrushing'}      = 'False';
    $header_hash->{'M0'}                    = {'WithinASL', 'False'};
}

sub grep_SliceOrder_info_for_JSON_file {
    my ($header_hash, $minc_full_path, $manufacturerPhilips) = @_;

    my ($extraHeader, $extraHeaderVal);
    my ($minc_header_name, $header_value);

    # If manufacturer is Philips, then add SliceOrder to the JSON manually
    ######## This is just for the BETA version #########
    ## See the TODO section for improvements needed in the future on SliceOrder ##
    if ($manufacturerPhilips == 1) {
        $extraHeader = "SliceOrder";
        $extraHeader =~ s/^\"+|\"$//g;
        if ($sliceOrderPhilips) {
            $extraHeaderVal = $sliceOrderPhilips;
        }
        else {
            print "   This is a Philips Scanner with no $extraHeader
                    defined at the command line argument 'slice_order_philips'.
                    Logging in the JSON as 'Not Supplied' \n" if $verbose;
        }
        $header_hash->{$extraHeader} = $extraHeaderVal;
        print "    $extraHeaderVal was added for Philips Scanners'
                $extraHeader \n" if $verbose;
    }
    else {
        # get the SliceTiming from the proper header
        # split on the ',', remove trailing '.' if exists, and add [] to make it a list
        $minc_header_name = 'dicom_0x0019:el_0x1029';
        $extraHeader = "SliceTiming";
        $header_value = &NeuroDB::MRI::fetch_header_info(
            $minc_full_path, $minc_header_name
        );
        # Some earlier dcm2mnc converters created SliceTiming with values
        # such as 0b, -91b, -5b, etc... so those MINC headers with `b`
        # in them, do not report, just report that is it not supplied
        # due likely to a dcm2mnc error
        # print this message, even if NOT in verbose mode to let the user know
        if ($header_value) {
            if ($header_value =~ m/b/) {
                $header_value = "not supplied as the values read from the MINC header seem erroneous, due most likely to a dcm2mnc conversion problem";
                print "    SliceTiming is " . $header_value . "\n";
            }
            else {
                $header_value = [ map {$_ / 1000} split(",", $header_value) ];
                print "    SliceTiming $header_value was added \n" if $verbose;
            }
        }
        $header_hash->{$extraHeader} = $header_value;
    }
}

sub grep_TaskName_info_for_JSON_file {
    my ($bids_categories_hash, $header_hash) = @_;

    my ($extraHeader, $extraHeaderVal);
    $extraHeader = "TaskName";
    $extraHeader =~ s/^\"+|\"$//g;
    # Assumes the SubCategory for funct BIDS categories in the BIDS
    # database tables follow the naming convention `task-rest` or `task-memory`,
    $extraHeaderVal = $bids_categories_hash->{'BIDSScanTypeSubCategory'};
    # so strip the `task-` part to get the TaskName
    # $extraHeaderVal =~ s/^task-//;
    # OR in general, strip everything up until and including the first hyphen
    $extraHeaderVal =~ s/^[^-]+\-//;
    $header_hash->{$extraHeader} = $extraHeaderVal;
    print "    TASKNAME added for bold: $extraHeader
                    with value $extraHeaderVal\n" if $verbose;
}

sub grep_phasediff_associated_magnitude_files {
    my ($loris_files_list, $phasediff_loris_hash, $dbh) = @_;

    # grep phasediff session ID and series number to grep the corresponding
    # magnitude files
    my $phasediff_sessionID    = $phasediff_loris_hash->{'sessionID'};
    my $phasediff_seriesNumber = $phasediff_loris_hash->{'seriesNumber'};

    # fetch the acquisition protocol ID that corresponds to the magnitude files
    my $magnitudeAcqProtID = grep_acquisitionProtocolID_from_BIDS_scan_type($dbh);

    my %magnitude_files;
    foreach my $row (keys %$loris_files_list) {
        my $acqProtID    = $loris_files_list->{$row}{'AcquisitionProtocolID'};
        my $sessionID    = $loris_files_list->{$row}{'sessionID'};
        my $echoNumber   = $loris_files_list->{$row}{'echoNumber'};
        my $seriesNumber = $loris_files_list->{$row}{'seriesNumber'};

        # skip the row unless the file is a magnitude protocol of the same
        # session with the series number equal to the phasediff's series
        # number - 1
        next unless ($acqProtID == $magnitudeAcqProtID
            && $sessionID == $phasediff_sessionID
            && $seriesNumber == ($phasediff_seriesNumber - 1)
        );

        # add the different magnitude files to the magnitude_files hash
        # with their information based on their EchoNumber
        $magnitude_files{"Echo$echoNumber"} = $loris_files_list->{$row};
    }

    return \%magnitude_files;
}

sub grep_acquisitionProtocolID_from_BIDS_scan_type {
    my ($dbh) = @_;

    ($query = <<QUERY ) =~ s/\n/ /g;
SELECT
  mst.ID
FROM bids_mri_scan_type_rel bmstr
  JOIN mri_scan_type mst ON bmstr.MRIScanTypeID=mst.ID
  JOIN bids_scan_type bst USING (BIDSScanTypeID)
WHERE
  bst.BIDSScanType = ?
QUERY

    # Prepare and execute query
    $sth = $dbh->prepare($query);
    $sth->execute('magnitude');
    if ( $sth->rows > 0 ) {
        my $acqProtID = $sth->fetchrow_array();
        return $acqProtID;
    }
    else {
        print "     no 'magnitude' scan type was found in BIDS tables\n" if $verbose;
    }
}

sub create_BIDS_magnitude_files {
    my ($phasediff_filename, $magnitude_files_hash) = @_;

    # grep the phasediff run number to be used for the magnitude file
    my $phasediff_run_nb;
    if ($phasediff_filename =~ m/_(run-\d\d\d)_/g) {
        $phasediff_run_nb = $1;
    } else {
        "WARNING: could not find the run number for $phasediff_filename\n";
    }

    foreach my $row (keys %$magnitude_files_hash) {
        my $minc           = $magnitude_files_hash->{$row}{'file'};
        my $acqProtocolID  = $magnitude_files_hash->{$row}{'AcquisitionProtocolID'};
        my $echo_nb        = $magnitude_files_hash->{$row}{'echoNumber'};
        my $fileID         = $magnitude_files_hash->{$row}{'fileID'};

        ### check if the MINC file can be found on the file system
        my $minc_full_path = "$dataDir/$minc";
        if (! -e $minc_full_path) {
            print "\nCould not find the following MINC file: $minc_full_path\n"
                if $verbose;
            next;
        }

        ### Get the BIDS scans label information
        my ($bids_categories_hash) = grep_bids_scan_categories_from_db($dbh, $acqProtocolID);
        unless ($bids_categories_hash) {
            print "$minc will not be converted into BIDS as no entries were found "
                . "in the bids_mri_scan_type_rel table for that scan type.\n";
            next;
        }

        ### determine the BIDS NIfTI filename
        my $niftiFileName = determine_bids_nifti_file_name(
            $minc,                 $prefix,           $magnitude_files_hash->{$row},
            $bids_categories_hash, $phasediff_run_nb, $echo_nb
        );

        ### create the BIDS directory where the NIfTI file would go
        my $bids_scan_directory = determine_BIDS_scan_directory(
            $magnitude_files_hash->{$row}, $bids_categories_hash, $destDir
        );
        make_path($bids_scan_directory) unless(-d  $bids_scan_directory);

        ### Convert the MINC file into the BIDS NIfTI file
        print "\n*******Currently processing $minc_full_path********\n";
        #  mnc2nii command then gzip it because BIDS expects it this way
        my $success = create_nifti_bids_file(
            $dataDir, $minc, $bids_scan_directory, $niftiFileName, $fileID,
            $bids_categories_hash->{'BIDSCategoryName'}
        );
        unless ($success) {
            print "WARNING: mnc2nii conversion failed for $minc.\n";
            next;
        }

        #  create json information from MINC files header;
        my ($json_filename, $json_fullpath) = determine_BIDS_scan_JSON_file_path(
            $niftiFileName, $bids_scan_directory
        );

        my ($header_hash) = gather_parameters_for_BIDS_JSON_file(
            $minc_full_path, $json_filename, $bids_categories_hash
        );

        unless (-e $json_fullpath) {
            write_BIDS_JSON_file($json_fullpath, $header_hash);
            my $modalitytype = $bids_categories_hash->{'BIDSCategoryName'};
            registerBidsFileInDatabase(
                $json_fullpath, 'image', 'json', $fileID,
                $modalitytype,  undef,   undef
            );
        }
    }
}

sub makeTaskTextFiles {
    my ($dbh, $sessionID, $task_type, $niftiFullPath) = @_;

    ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  FileID,
  File,
  mst.Scan_type
FROM files f
JOIN mri_scan_type mst ON (mst.ID=f.AcquisitionProtocolID)

WHERE FileType = "txt" AND mst.Scan_type = ? AND SessionID = ?
QUERY

    my $scan_type = "task-$task_type" . "-events";
    my $sth = $dbh->prepare($query);
    $sth->execute($scan_type, $sessionID);

    my %event_file_list;

    while ( my $rowhr = $sth->fetchrow_hashref()) {
        $event_file_list{'fileID'}     = $rowhr->{'FileID'};
        $event_file_list{'file'}       = $rowhr->{'File'};
        $event_file_list{'scanType'}   = $rowhr->{'Scan_type'};
    }

    return unless (keys %event_file_list);

    my $textFileFullPath = $niftiFullPath;
    $textFileFullPath =~ s/\.nii(\.gz)?/_events.txt/g;

    unless (-e $textFileFullPath) {
        my $cmd = "cp $dataDir/$event_file_list{'file'} $textFileFullPath";
        system($cmd);
        registerBidsFileInDatabase(
            $textFileFullPath, 'image', 'txt', $event_file_list{'fileID'},
            undef,             undef,   undef
        );
    }

}

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

        my $closest_fmap_seriesnb = getClosestNumberInArray(
            $series_number, \@list_of_fieldmap_seriesnb
        );

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

sub updateT1IntendedFor {
    my ($dbh, $files_hash, $tarchiveID) = @_;

    my $scout_seriesnb_arr = grepAAHScoutSeriesNumbers($dbh, $tarchiveID);
    my $t1_hash            = grepListOfT1($files_hash);
    my $nii_files_hash     = grepListOfNiiFilesOrganizedBySeriesNumber($files_hash);

    if (scalar @$scout_seriesnb_arr == 1) {
        # only one scout so T1s are intended for all series
        for my $t1_seriesnb (keys %$t1_hash) {
            my $t1_json_path = $t1_hash->{$t1_seriesnb};
            my $tmp_hash     = { %$nii_files_hash };
            delete($tmp_hash->{$t1_seriesnb});    # remove the T1 entry from the list of nii
            my @intendedFor = values %$tmp_hash;  # grep the list of nii files associated with the t1
            updateJSONfileWithIntendedFor($t1_json_path, \@intendedFor);
        }

    } elsif (scalar @$scout_seriesnb_arr > 1) {
        # then spit the intended for based on the SCOUTs
        for (my $idx = 0; $idx < scalar @$scout_seriesnb_arr; $idx++) {
            my $min_seriesnb = @$scout_seriesnb_arr[$idx];
            my $max_seriesnb = ($idx + 1 < scalar @$scout_seriesnb_arr) ? @$scout_seriesnb_arr[$idx + 1] : 100;
            my $nii_tmp_hash = { %$nii_files_hash };
            for my $series_nb_key (keys %$nii_tmp_hash) {
                unless ($min_seriesnb < $series_nb_key && $series_nb_key < $max_seriesnb) {
                    delete($nii_tmp_hash->{$series_nb_key});
                }
            }
            my $t1_tmp_hash = { %$t1_hash };
            for my $t1_seriesnb (keys %$t1_tmp_hash) {
                next unless ($min_seriesnb < $t1_seriesnb && $t1_seriesnb < $max_seriesnb);
                my $t1_json_path = $t1_hash->{$t1_seriesnb};
                delete($nii_tmp_hash->{$t1_seriesnb});    # remove the T1 entry from the list of nii
                my @intendedFor = values %$nii_tmp_hash;  # grep the list of nii files associated with the t1
                updateJSONfileWithIntendedFor($t1_json_path, \@intendedFor);
            }
        }
    }

}

sub updateJSONfileWithIntendedFor {
    my ($json_filepath, $intendedFor) = @_;

    # read the JSON file
    my $json_content = do {
        open(FILE, "<", $json_filepath) or die "Can not open $json_filepath: $!\n";
        local $/;
        <FILE>
    };
    close FILE;

    my $json_obj  = new JSON;
    my %json_data = %{ $json_obj->decode($json_content) };
    $json_data{'IntendedFor'} = $intendedFor;
    write_BIDS_JSON_file($json_filepath, \%json_data);
}

sub grepAAHScoutSeriesNumbers {
    my ($dbh, $tarchiveID) = @_;

    (my $query = <<QUERY ) =~ s/\n/ /g;
SELECT DISTINCT
  SeriesNumber
FROM
  tarchive_series
WHERE
  TarchiveID = ? AND SeriesDescription='AAHScout'
QUERY

    my $sth = $dbh->prepare($query);
    $sth->execute($tarchiveID);

    my @scout_seriesnb_arr;
    while (my $rowhr = $sth->fetchrow_hashref()) {
        push(@scout_seriesnb_arr, $rowhr->{'SeriesNumber'});
    }

    return \@scout_seriesnb_arr;
}

sub grepListOfT1 {
    my ($files_hash) = @_;

    my %t1_hash;
    for my $rowid (%$files_hash) {
        # if it is a magnitude file, then BIDSScanType key is not present so skip it
        next unless ($files_hash->{$rowid}{'BIDSScanType'});
        next unless ($files_hash->{$rowid}{'BIDSScanType'} eq "T1w"); # skip unless T1
        my $t1_series_nb = $files_hash->{$rowid}{'seriesNumber'};
        my $t1_json_file = $files_hash->{$rowid}{'jsonFilePath'};
        $t1_hash{$t1_series_nb} = $t1_json_file;
    }

    return \%t1_hash;
}

sub grepListOfNiiFilesOrganizedBySeriesNumber {
    my ($files_hash) = @_;

    my %nii_files_hash;
    for my $rowid (%$files_hash) {
        # if it is a magnitude file, then skip it since no JSON associated in hash
        next unless ($files_hash->{$rowid}{'BIDSScanType'});
        next if ($files_hash->{$rowid}{'BIDSScanType'} eq "magnitude");
        my $series_nb     = $files_hash->{$rowid}{'seriesNumber'};
        my $nii_file      = $files_hash->{$rowid}{'niiFileName'};
        my $bids_category = $files_hash->{$rowid}{'BIDSCategoryName'};
        my $visit_label   = $files_hash->{$rowid}{'visitLabel'};
        $nii_files_hash{$series_nb} = "ses-$visit_label/$bids_category/$nii_file";
    }

    return \%nii_files_hash;
}


sub getClosestNumberInArray {
    my ($val, $arr) = @_;

    my @test = sort { abs($a - $val) <=> abs($b - $val)} @$arr;

    return $test[0];
}


sub registerBidsFileInDatabase {
    my ($filepath, $filelevel, $filetype, $fileid, $modalitytype, $behaviouraltype, $sessionID) = @_;

    return unless (-e $filepath);

    $filepath =~ s/$dataDir\///g;

    (my $query = <<QUERY ) =~ s/\n/ /g;
INSERT INTO bids_export_files SET
    FileID          = ?,    BIDSFileLevel   = ?,
    FileType        = ?,    FilePath        = ?,
    ModalityType    = ?,    BehaviouralType = ?,
    SessionID       = ?
QUERY

    # Prepare and execute query
    my $sth = $dbh->prepare($query);
    $sth->execute(
        $fileid,       $filelevel,       $filetype,  $filepath,
        $modalitytype, $behaviouraltype, $sessionID
    );


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

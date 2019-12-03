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
use JSON;

use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::ExitCodes;

use NeuroDB::Database;
use NeuroDB::DatabaseException;

use NeuroDB::objectBroker::ObjectBrokerException;
use NeuroDB::objectBroker::ConfigOB;



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




# ----------------------------------------------------------------
## Establish database connection
# ----------------------------------------------------------------

# old database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# new Moose database connection
my $db  = NeuroDB::Database->new(
    databaseName => $Settings::db[0],
    userName     => $Settings::db[1],
    password     => $Settings::db[2],
    hostName     => $Settings::db[3]
);
$db->connect();

print "\n==> Successfully connected to database \n";


# ----------------------------------------------------------------
## Get config setting using ConfigOB
# ----------------------------------------------------------------

my $configOB = NeuroDB::objectBroker::ConfigOB->new(db => $db);

my $dataDir  = $configOB->getDataDirPath();
my $binDir   = $configOB->getMriCodePath();
my $prefix   = $configOB->getPrefix();


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
open DATADESCINFO, ">$dataDescFile" or die "Can not write file $dataDescFile: $!\n";
DATADESCINFO->autoflush(1);
select(DATADESCINFO);
select(STDOUT);
my %dataset_desc_hash = (
    'BIDSVersion'           => $BIDSVersion,
    'Name'                  => $datasetName,
    'LORISScriptVersion'    => $LORISScriptVersion,
    'License'               => 'GLPv3',
    'Authors'               => ['LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience'],
    'HowToAcknowledge'      => 'Dataset generated using LORIS and LORIS-MRI; please cite this paper: Das S. et al (2011). LORIS: a web-based data management system for multi-center studies, Frontiers in Neuroinformatics, 5:37 ',
    'LORISReleaseVersion'   => $MRIVersion);
my $json = encode_json \%dataset_desc_hash;
print DATADESCINFO "$json\n";
close DATADESCINFO;

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

    my %file_list = &getFileList( $dbh, $dataDir, $givenTarchiveID );

    # Make NIfTI files and JSON headers out of those MINC
    &makeNIIAndHeader( $dbh, %file_list);
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

=head3 getFileList($dbh, $dataDir, $givenTarchiveID)

This function will grep all the C<TarchiveID> and associated C<ArchiveLocation>
present in the C<tarchive> table and will create a hash of this information
including new C<ArchiveLocation> to be inserted into the database.

INPUTS:
    - $dbh             : database handler
    - $dataDir         : where the imaging files are located
    - $givenTarchiveID : the C<TarchiveID> under consideration

RETURNS:
    - %file_list       : hash with files for a given C<TarchiveID>

=cut

sub getFileList {

    my ($dbh, $dataDir, $givenTarchiveID) = @_;

    # Query to grep all file entries
    ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  FileID,
  File,
  AcquisitionProtocolID,
  c.CandID,
  s.Visit_label,
  SessionID
FROM
  files f
JOIN
  session s
ON
  s.ID=f.SessionID
JOIN
  candidate c
ON
  c.CandID=s.CandID
WHERE
  f.OutputType = 'native'
AND
  f.FileType = 'mnc'
AND
  c.Entity_type = 'Human'
AND
  f.TarchiveSource = ? 
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
        $i++;
    }
    return %file_list;

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
    my ($row, $mriScanType, $BIDSCategory, $BIDSSubCategory, $BIDSScanType, $BIDSEchoNumber, $destDirFinal);
    foreach $row (keys %file_list) {
        my $fileID            = $file_list{$row}{'fileID'};
        my $minc              = $file_list{$row}{'file'};
        my $fileAcqProtocolID = $file_list{$row}{'AcquisitionProtocolID'};
        my $candID            = $file_list{$row}{'candID'};
        my $visitLabelOrig    = $file_list{$row}{'visitLabel'};

        # Get the scan category (anat, func, dwi, to know which subdirectory to place files in
        ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  bmstr.MRIScanTypeID,
  bids_category.BIDSCategoryName,
  bids_scan_type_subcategory.BIDSScanTypeSubCategory,
  bids_scan_type.BIDSScanType,
  bmstr.BIDSEchoNumber,
  mst.Scan_type
FROM       bids_mri_scan_type_rel bmstr
JOIN       mri_scan_type mst          ON mst.ID = bmstr.MRIScanTypeID
JOIN       bids_category              USING (BIDSCategoryID)
JOIN       bids_scan_type             USING (BIDSScanTypeID)
LEFT JOIN  bids_scan_type_subcategory USING (BIDSScanTypeSubCategoryID)
WHERE      mst.ID = ?
QUERY
        # Prepare and execute query
        my $sth = $dbh->prepare($query);
        $sth->execute($fileAcqProtocolID);
        my $rowhr = $sth->fetchrow_hashref();
        unless ($rowhr) {
            print "$minc will not be converted into BIDS as no entries were found "
                  . "in the bids_mri_scan_type_rel table for that scan type.\n";
            next;
        }
        $mriScanType     = $rowhr->{'Scan_type'};
        $BIDSCategory    = $rowhr->{'BIDSCategoryName'};
        $BIDSSubCategory = $rowhr->{'BIDSScanTypeSubCategory'};
        $BIDSScanType    = $rowhr->{'BIDSScanType'};
        $BIDSEchoNumber  = $rowhr->{'BIDSEchoNumber'};

        my $mincBase            = basename($minc);
        my $nifti               = $mincBase;

        # Make extension nii instead of minc
        $nifti                =~ s/mnc/nii/g;

        # If Visit Label contains underscores, remove them
        my $visitLabel        = $visitLabelOrig;
        $visitLabel           =~ s/_//g;

        # Remove prefix; i.e project name; and add sub- and ses- in front of
        # CandID and Visit label
        my $remove  = $prefix . "_" . $candID . "_" . $visitLabelOrig;
        my $replace = "sub-" . $candID . "_ses-" . $visitLabel;
        # sequences with multi-echo need to have echo-1. echo-2, etc... appended to the filename
        # TODO: add a check if the sequence is indeed a multi-echo (check SeriesUID
        # and EchoTime from the database), and if not set, issue an error
        # and exit and ask the project to set the BIDSMultiEcho for these sequences
        # Also need to add .JSON for those multi-echo files
        if ($BIDSEchoNumber) {
            $replace .= "_echo-" . $BIDSEchoNumber;
        }
        $nifti                =~ s/$remove/$replace/g;

        # make the filename have the BIDS Scan type name, in case the project
        # Scan type name is not compliant;
        # and append the word 'run' before run number
        $remove = $mriScanType . "_";
        # If the file is of type fMRI; need to add a BIDS subcategory type
        # for example, task-rest for resting state fMRI
        # or task-memory for memory task fMRI
        # Exclude ASL as these are under 'func' for BIDS but will not have BIDSScanTypeSubCategory
        if ($BIDSCategory eq 'func' && $BIDSScanType !~ m/asl/i) {
            if ($BIDSSubCategory) {
                $replace = $BIDSSubCategory . "_run-";
            }
            else {
                print STDERR "\n ERROR: Files of BIDS Category type 'func' and
                                 which are fMRI need to have their
                                 BIDSScanTypeSubCategory defined. \n\n";
                exit $NeuroDB::ExitCodes::PROJECT_CUSTOMIZATION_FAILURE;
            }
        } else {
            $replace = "run-";
        }
        $nifti =~ s/$remove/$replace/g;

        # find position of the last dot, so where the extension starts
        my ($base,$path,$ext) = fileparse($nifti, qr{\..*});
        $base = $base . "_" . $BIDSScanType;
        $nifti = $base . $ext;

        $destDirFinal = $destDir . "/sub-" . $candID . "/ses-" . $visitLabel . "/" . $BIDSCategory;
        make_path($destDirFinal) unless(-d  $destDirFinal);

        my $mincFullPath = $dataDir . "/" . $minc;
        if (-e $mincFullPath) {
            print "\n*******Currently processing $mincFullPath********\n";
            #  mnc2nii command then gzip it because BIDS expects it this way
            my $m2n_cmd = "mnc2nii -nii -quiet " .
                            $dataDir . "/" . $minc . " " .
                            $destDirFinal . "/" . $nifti;
            system($m2n_cmd);

            # the -f flag is to force overwrite of an existing output; otherwise, 
            # the user is prompted for every file if they would like to override
            my $gzip_cmd = "gzip -f " . $destDirFinal . "/" . $nifti;
            system($gzip_cmd);

            #  create json information from MINC files header;
            my (@headerNameArr, $headerNameArr,
                @headerNameDBArr, $headerNameDBArr,
                @headerNameMINCArr, $headerNameMINCArr,
                $headerName, $headerNameDB,
                $headerNameMINC, $headerVal,
                $headerFile);


            $headerFile         = $nifti;
            $headerFile         =~ s/nii/json/g;
            open HEADERINFO, ">$destDirFinal/$headerFile";
            HEADERINFO->autoflush(1);
            select(HEADERINFO);
            select(STDOUT);

            my %header_hash;
            my $header_hash;
            my $currentHeaderJSON;
   
            # get this info from the MINC header instead of the database
            # Name is as it appears in the database
            # slice order is needed for resting state fMRI
            @headerNameMINCArr = (
                'acquisition:repetition_time','study:manufacturer',
                'study:device_model','study:field_value',
                'study:serial_no','study:software_version',
                'acquisition:receive_coil','acquisition:scanning_sequence',
                'acquisition:echo_time','acquisition:inversion_time',
                'dicom_0x0018:el_0x1314', 'study:institution',
                'acquisition:slice_order'
            );
            # Equivalent name as it appears in the BIDS specifications
            @headerNameArr = (
                "RepetitionTime","Manufacturer",
                "ManufacturerModelName","MagneticFieldStrength",
                "DeviceSerialNumber","SoftwareVersions",
                "ReceiveCoilName","PulseSequenceType",
                "EchoTime","InversionTime",
                "FlipAngle", "InstitutionName",
                "SliceOrder"
            );

            my $mincFileName = $dataDir . "/" . $minc;
            my $manufacturerPhilips = 0;
            my ($extraHeader, $extraHeaderVal);

            foreach my $j (0..scalar(@headerNameMINCArr)-1) {
                $headerNameMINC = $headerNameMINCArr[$j];
                $headerName   = $headerNameArr[$j];
                $headerName   =~ s/^\"+|\"$//g;
                print "Adding now $headerName header to $headerFile\n" if $verbose;

                $headerVal = NeuroDB::MRI::fetch_header_info(
                    $mincFileName, $headerNameMINC
                );
                # Some headers need to be explicitely converted to floats in Perl
                # so json_encode does not add the double quotation around them
                my @convertToFloat = [
                    'acquisition:repetition_time', 'acquisition:echo_time',
                    'acquisition:inversion_time',  'dicom_0x0018:el_0x1314'
                ];
                $headerVal *= 1 if ($headerVal && $headerNameMINC ~~ @convertToFloat);

                if (defined($headerVal)) {
                    $header_hash{$headerName} = $headerVal;
                        print "     $headerName was found for $mincFileName with value $headerVal\n" if $verbose;

                    # If scanner is Philips, store this as condition 1 being met
                    if ($headerNameMINC eq 'study:manufacturer' && $headerVal =~ /Philips/i) {
                        $manufacturerPhilips = 1;
                    }
                }
                else {
                    print "     $headerName was not found for $mincFileName\n" if $verbose;
                }
            }
            
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
                $header_hash{$extraHeader} = $extraHeaderVal;
                print "    $extraHeaderVal was added for Philips Scanners'
                $extraHeader \n" if $verbose;
            } else {
                # get the SliceTiming from the proper header
                # split on the ',', remove trailing '.' if exists, and add [] to make it a list
                $headerNameMINC = 'dicom_0x0019:el_0x1029';
                $extraHeader    = "SliceTiming";
                $headerVal      =  &NeuroDB::MRI::fetch_header_info(
                    $mincFileName, $headerNameMINC
                );
                # Some earlier dcm2mnc converters created SliceTiming with values
                # such as 0b, -91b, -5b, etc... so those MINC headers with `b`
                # in them, do not report, just report that is it not supplied
                # due likely to a dcm2mnc error
                # print this message, even if NOT in verbose mode to let the user know
                if ($headerVal =~ m/b/ ) {
                    $headerVal = "not supplied as the values read from the MINC header seem erroneous, due most likely to a dcm2mnc conversion problem";
                    print "    SliceTiming is " .  $headerVal . "\n";
                }
                else {
                    $headerVal = [ map {$_ / 1000} split(",", $headerVal) ];
                    print "    SliceTiming $headerVal was added \n" if $verbose;
                }
                $header_hash{$extraHeader} = $headerVal;
            } 

            # for fMRI, we need to add TaskName which is e.g task-rest in the case of resting-state fMRI
            if ($BIDSCategory eq 'func' && $BIDSScanType !~ m/asl/i) {
                $extraHeader = "TaskName";
                $extraHeader =~ s/^\"+|\"$//g;
                # Assumes the SubCategory for funct BIDS categories in the BIDS
                # database tables follow the naming convention
                # `task-rest` or `task-memory`,
                $extraHeaderVal = $BIDSSubCategory;
                # so strip the `task-` part to get the TaskName
                # $extraHeaderVal =~ s/^task-//;
                # OR in general, strip everything up until and including the first hyphen
                $extraHeaderVal =~ s/^[^-]+\-//;
                $header_hash{$extraHeader} = $extraHeaderVal;
                    print "    TASKNAME added for bold: $extraHeader
                    with value $extraHeaderVal\n" if $verbose;
            }
            $currentHeaderJSON = encode_json \%header_hash;
            print HEADERINFO "$currentHeaderJSON";
            close HEADERINFO;
        }
        else {
            print "\nCould not find the following minc file: $mincFullPath\n"
                if $verbose;;
        }


        # DWI files need 2 extra special files; .bval and .bvec
        if ($BIDSScanType eq 'dwi') {
            my ( @headerNameBVALDBArr, $headerNameBVALDBArr,
                 @headerNameBVECDBArr, $headerNameBVECDBArr,
                 $headerName, $headerNameDB, $headerVal, $bvalFile, $bvecFile);
            @headerNameBVALDBArr      = ("acquisition:bvalues");
            @headerNameBVECDBArr      = ("acquisition:direction_x","acquisition:direction_y","acquisition:direction_z");

            #BVAL first
            $bvalFile         = $nifti;
            $bvalFile         =~ s/nii/bval/g;
            &fetchBVAL_BVEC( $dbh, $nifti, $bvalFile, $fileID, $destDirFinal, @headerNameBVALDBArr);
            #BVEC next
            $bvecFile         = $nifti;
            $bvecFile         =~ s/nii/bvec/g;
            &fetchBVAL_BVEC( $dbh, $nifti, $bvecFile, $fileID, $destDirFinal, @headerNameBVECDBArr);
        }
    }
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
    my ( $dbh, $nifti, $bvFile, $fileID, $destDirFinal, @headerNameBVDBArr ) = @_;
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

#! /usr/bin/perl

use strict;
use warnings;
use Getopt::Tabular;
use File::Path qw/ make_path /;
use File::Basename;
use NeuroDB::DBI;
use JSON;

my $profile = undef;
my $tarchiveID = undef;
my $BIDSVersion = "1.0.2";
my $datasetName = undef;

my @opt_table = (
    [ "-profile", "string", 1, \$profile,
      "name of config file in ../dicom-archive/.loris_mri"
    ],
    [ "-tarchive_id", "string", 1, \$tarchiveID,
      "tarchive_id of the .tar to be processed from tarchive table"
    ],
    [ "-dataset_name", "string", 1, \$datasetName,
      "Name/Description of the dataset about to be generated in BIDS format; for example CCNA_First_Sample_Data"
    ]
); 

my $Help = <<HELP;

This script will create a BIDS compliant NII file structure of the minc files
currently present in the assembly/ directory. If tarchive_id is specified,
only the images from that archive will be processed, otherwise, when no
tarchive_id is specified, all files in assembly/ will be included in the BIDS
structure.
Requires JSON library for Perl. Run sudo apt-get install libjson-perl to get it.

HELP

my $Usage = <<USAGE;

Usage: $0 -help to list options

USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;

################################################################
################### input option error checking ################
################################################################
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ($profile && !@Settings::db) {
    print "\n\tERROR: You don't have a configuration file named ".
          "'$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n";
    exit 2;
}

if ( !$datasetName ) {
    print $Help;
    print "$Usage\n\tERROR: The dataset name needs to be provided. "
      . "it is required by BIDS specifications to populate the "
      . "dataset_description.json file \n\n";
    exit 3;
}

################################################################
######### Establish database connection ########################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\n==> Successfully connected to database \n";

################################################################
#### This setting is in the ConfigSettings table   #############
################################################################
my $dataDir = &NeuroDB::DBI::getConfigSetting(
                            \$dbh,'dataDirBasepath'
                            );
my $prefix = &NeuroDB::DBI::getConfigSetting(
                            \$dbh,'prefix'
                            );
$dataDir    =~ s/\/$//g;

# Make destination directory for the NII files
# same level as assmebly/ directory but named as BIDS/
my $destDir = $dataDir . "/BIDS";
make_path($destDir) unless(-d  $destDir);

# Create the dataset_description.json file
my $dataDescFileName = "dataset_description.json";
my $dataDescFile     = $destDir . "/" . $dataDescFileName;
unless (-e $dataDescFile) {
    print "\n*******Creating the dataset description file*******\n";
    open DATADESCINFO, ">$dataDescFile";
    DATADESCINFO->autoflush(1);
    select(DATADESCINFO);
    select(STDOUT);
    my %dataset_desc_hash = ('BIDSVersion' => $BIDSVersion, 'Name' => $datasetName);
    my $json = encode_json \%dataset_desc_hash;
    print DATADESCINFO "$json\n";
    close DATADESCINFO;
}

my ($query, $sth);

# Query to grep all distinct TarchiveIDs from the database 
if (!defined($tarchiveID)) {
    ( $query = <<QUERY ) =~ s/\n/ /g;
SELECT DISTINCT
  TarchiveID
FROM
  tarchive t
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
  tarchive t
WHERE
  TarchiveID = ?
QUERY
    # Prepare and execute query
    $sth = $dbh->prepare($query);
    $sth->execute($tarchiveID);
}
while ( my $rowhr = $sth->fetchrow_hashref()) {
    my $givenTarchiveID = $rowhr->{'TarchiveID'};
    print "\n*******Currently creating a BIDS directory of nii files for ".
            "tarchiveID $givenTarchiveID********\n";
################################################################
################ Grep files list in a hash #####################
######### If no TarchiveID is given loop through all ###########
###### Else, use the given TarchiveID at the command line ######
################################################################

    my %file_list = &getFileList( $dbh, $dataDir, $givenTarchiveID );

################################################################
##### Make nii files and JSON headers out of those minc ########
################################################################
    &makeNIIAndHeader( $dbh, %file_list);
    if (defined($tarchiveID)) {
        print "\nFinished tarchiveID $givenTarchiveID\n";
    }
}
if (!defined($tarchiveID)) {
    print "\nFinished all Tarchives\n";
}
$dbh->disconnect();
exit 0;


=pod
This function will grep all the TarchiveID and associated ArchiveLocation
present in the tarchive table and will create a hash of this information
including new ArchiveLocation to be inserted into the DB.
Input:  - $dbh             = database handler
        - $dataDir         = where the data (files) is located
        - $givenTarchiveID = the TarchiveID under consideration
Output: - %file_list       = hash with files for a given TarchiveID
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
        my $fileID            = $rowhr->{'FileID'};
        my $fileName          = $rowhr->{'File'};
        my $fileAcqProtocolID = $rowhr->{'AcquisitionProtocolID'};
        my $fileCandID        = $rowhr->{'CandID'};
        my $fileSessionID     = $rowhr->{'SessionID'};
        my $fileVisitLabel    = $rowhr->{'Visit_label'};
    
        $file_list{$i}{'fileID'}                = $fileID;
        $file_list{$i}{'file'}                  = $fileName;
        $file_list{$i}{'AcquisitionProtocolID'} = $fileAcqProtocolID;
        $file_list{$i}{'candID'}                = $fileCandID;
        $file_list{$i}{'sessionID'}             = $fileName;
        $file_list{$i}{'visitLabel'}            = $fileVisitLabel;
        $i++;
    }
    return %file_list;

}

=pod
This function will make .nii files out of the .mnc files and puts them in BIDS format.
It also creates a .json file for each .nii file by getting the header values from the 
parameter_file table. Header information is selected based on the BIDS document 
(http://bids.neuroimaging.io/bids_spec1.0.2.pdf ; pages 14 through 17). 
Input:  - $dbh = database handler
        - $file_list = hash with filesinformation.
=cut
sub makeNIIAndHeader {
    
    my ( $dbh, %file_list) = @_;
    my ($row, $scanType, $BIDSCategory, $BIDSScanType, $destDirFinal);
    foreach $row (keys %file_list) {
        my $fileID            = $file_list{$row}{'fileID'};
        my $minc              = $file_list{$row}{'file'};
        my $fileAcqProtocolID = $file_list{$row}{'AcquisitionProtocolID'};
        my $candID            = $file_list{$row}{'candID'};
        my $visitLabelOrig    = $file_list{$row}{'visitLabel'};

        # Get the scan category (anat, func, dwi, to know which subdirectory to place files in
        ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  Scan_type,
  BIDS_category,
  BIDS_Scan_type
FROM
  mri_scan_type mst
WHERE
  mst.ID = ?
QUERY
        # Prepare and execute query
        my $sth = $dbh->prepare($query);
        $sth->execute($fileAcqProtocolID);
        my $rowhr = $sth->fetchrow_hashref();
        $scanType     = $rowhr->{'Scan_type'};
        $BIDSCategory = $rowhr->{'BIDS_category'};
        $BIDSScanType = $rowhr->{'BIDS_Scan_type'};

        my $mincBase          = basename($minc);
        my $nifti             = $mincBase;

        # Make extension nii instead of minc
        $nifti                =~ s/mnc/nii/g;

        # If Visit Label contains underscores, remove them
        my $visitLabel        = $visitLabelOrig;
        $visitLabel           =~ s/_//g;

        # Remove prefix; i.e project name; and add sub- and ses- in front of CandID and Visit label
        my $remove            = $prefix . "_" . $candID . "_" . $visitLabelOrig;
        my $replace           = "sub-" . $candID . "_ses-" . $visitLabel;
        $nifti                =~ s/$remove/$replace/g;

        # make the filename have the BIDS Scan type name, in case the project Scan type name is not compliant;
        # and append the word 'run' before run number
        $remove = $scanType . "_";
        if ($BIDSCategory eq 'func') {
            # If the file is functional; need to add a leading 'task' before BIDS scan type
            $replace = "task-" . $BIDSScanType . "_run-";
        } else {
            $replace = "run-";
        }
        $nifti =~ s/$remove/$replace/g;

        # find position of the last dot, so where the extension starts
        my ($base,$path,$ext) = fileparse($nifti, qr{\..*});
        # If the file is functional; need to add a trailing 'bold' before the extension
        # otherwise, add the real BIDSScanType in the end
        if ($BIDSCategory eq 'func') {
            $base = $base . "_bold";
        } else {
            $base = $base . "_" . $BIDSScanType;        
        }
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

            #  create json information from minc files header; 
            my (@headerNameArr, $headerNameArr,
                @headerNameDBArr, $headerNameDBArr,
                @headerNameMINCArr, $headerNameMINCArr,
                $headerName, $headerNameDB, $headerNameMINC, $headerVal, $headerFile);


            $headerFile         = $nifti;
            $headerFile         =~ s/nii/json/g;
            open HEADERINFO, ">$destDirFinal/$headerFile";
            HEADERINFO->autoflush(1);
            select(HEADERINFO);
            select(STDOUT);

            my %header_hash;
            my $header_hash;
            my $currentHeaderJSON;
   
            # get this info from the mincheader instead of the database
            # Name as it appears in the database
            # slice order is needed for rs-FMRI
            @headerNameMINCArr      = ('acquisition:repetition_time','study:manufacturer','study:device_model','study:field_value',
                                'study:serial_no','study:software_version','acquisition:receive_coil','acquisition:scanning_sequence',
                                'acquisition:echo_time','acquisition:inversion_time','dicom_0x0018:el_0x1314', 'study:institution','acquisition:slice_order');
            # Equivalent name as it appears in the BIDS specifications
            @headerNameArr  = ("RepetitionTime","Manufacturer","ManufacturerModelName","MagneticFieldStrength",
                                "DeviceSerialNumber","SoftwareVersions","ReceiveCoilName","PulseSequenceType",
                                "EchoTime","InversionTime","FlipAngle", "InstitutionName", "SliceOrder");

            my $mincFileName = $dataDir . "/" . $minc;
            my $manufacturerPhilips = 0;
            my ($extraHeader, $extraHeaderVal);

            foreach my $j (0..scalar(@headerNameMINCArr)-1) {
                $headerNameMINC = $headerNameMINCArr[$j];
                $headerName   = $headerNameArr[$j];
                $headerName   =~ s/^\"+|\"$//g;
                print "Adding now $headerName header to $headerFile\n";

                $headerVal    =   &fetchMincHeader($mincFileName,$headerNameMINC);
                # Some headers need to be explicitely converted to floats in Perl
                # so json_encode does not add the double quotation around them
                if (($headerNameMINC eq 'acquisition:repetition_time') ||
                    ($headerNameMINC eq 'acquisition:echo_time') ||
                    ($headerNameMINC eq 'acquisition:inversion_time') ||
                    ($headerNameMINC eq 'dicom_0x0018:el_0x1314')) {
                        $headerVal *= 1;
                }


#                if (defined($headerVal) && ($headerVal ne '')) {
#                if (defined($headerVal) && ($headerVal != '')) {
                if (defined($headerVal)) {
                    $header_hash{$headerName} = $headerVal;
                    print "     $headerName was found for $mincFileName with value $headerVal\n";

                    # If scanner is Philips, store this as condition 1 being met
                    if ($headerNameMINC eq 'study:manufacturer' && $headerVal =~ /Philips/i) {
                        $manufacturerPhilips = 1;
                    }
                }
                else {
                    print "     $headerName was not found for $mincFileName\n";
                }
            }
            
            # If manufacturer is Philips, then add SliceOrder to the JSON manually
            ########## THE SLICEORDER SHOULD EVENTUALLY BECOME PROJECT CUSTOMIZABLE #######
            if ($manufacturerPhilips == 1) {
                $extraHeader = "SliceOrder";
                $extraHeader =~ s/^\"+|\"$//g;
                $extraHeaderVal = "ascending";
                $header_hash{$extraHeader} = $extraHeaderVal;
                    print "    $extraHeaderVal was added for Philps Scanners' $extraHeader \n";            
            } else {
                # get the SliceTiming from the proper header
                # for slicetiming; split on the ',', then remove trailing '.' if exists;
                # and add [] to make it a list
                $headerNameMINC = 'dicom_0x0019:el_0x1029';
                $extraHeader    = "SliceTiming";
                $headerVal      =  &fetchMincHeader($mincFileName,$headerNameMINC);
                $headerVal = [map {1 * $_} split(",", $headerVal)];
                    print "    SliceTiming $headerVal was added \n";
                $header_hash{$extraHeader} = $headerVal;
            } 

            # for fMRI, we need to add TaskName which is e.g task-rest in the case of resting-state fMRI
            if ($BIDSCategory eq 'func') {
                $extraHeader = "TaskName";
                $extraHeader =~ s/^\"+|\"$//g;
                $extraHeaderVal = "rest";
                $header_hash{$extraHeader} = $extraHeaderVal;
                    print "    TASKNAME added for bold: $extraHeader with value $extraHeaderVal\n";
            }
            $currentHeaderJSON = encode_json \%header_hash;
            print HEADERINFO "$currentHeaderJSON";
            close HEADERINFO;
        }
        else {
            print "\nCould not find the following minc file: $mincFullPath\n";
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
            open BVALINFO, ">$destDirFinal/$bvalFile";
            BVALINFO->autoflush(1);
            select(BVALINFO);
            select(STDOUT);
            foreach my $j (0..scalar(@headerNameBVALDBArr)-1) {
                $headerNameDB = $headerNameBVALDBArr[$j];
                $headerNameDB =~ s/^\"+|\"$//g;
                print "Adding now $headerName header to $bvalFile\n";
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
                    # There is one last trailing .; remove it
                    $headerVal =~ s/\.$//g;
                    print BVALINFO "$headerVal \n";
                    print "     $headerNameDB was found for $nifti with value $headerVal\n";
                }
                else {
                    print "     $headerNameDB was not found for $nifti\n";
                }
            }
            close BVALINFO;

            #BVEC next
            $bvecFile         = $nifti;
            $bvecFile         =~ s/nii/bvec/g;
            open BVECINFO, ">$destDirFinal/$bvecFile";
            BVECINFO->autoflush(1);
            select(BVECINFO);
            select(STDOUT);
            foreach my $j (0..scalar(@headerNameBVECDBArr)-1) {
                $headerNameDB = $headerNameBVECDBArr[$j];
                $headerNameDB =~ s/^\"+|\"$//g;
                print "Adding now $headerName header to $bvecFile\n";
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
                    print BVECINFO "$headerVal \n";
                    print "     $headerNameDB was found for $nifti with value $headerVal\n";
                }
                else {
                    print "     $headerNameDB was not found for $nifti\n";
                }
            }
            close BVECINFO;
        }
    }
}

=pod
This function parses the mincheader and look for specific field's value.
**Copied from register_processed_data.pl**
=cut

sub fetchMincHeader {
    my  ($file,$field)  =   @_;

#    my  $value  =   `mincheader $file | grep '$field' | awk '{print \$3, \$4, \$5, \$6}' | tr '\n' ' '`;
    my  $value  =   `mincheader $file | grep '$field' | cut -d= -f2- |sed -e 's/^ //'`;

    $value=~s/"//g;    #remove "
    $value=~s/^\s+//; #remove leading spaces
    $value=~s/\s+$//; #remove trailing spaces
    $value=~s/;//;    #remove ;

    return  $value;
}


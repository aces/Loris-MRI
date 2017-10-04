#! /usr/bin/perl

use strict;
use warnings;
use Getopt::Tabular;
use File::Path qw/ make_path /;
use File::Basename;
use NeuroDB::DBI;

my $profile = undef;
my $tarchiveID = undef;

my @opt_table = (
    [ "-profile", "string", 1, \$profile,
      "name of config file in ../dicom-archive/.loris_mri"
    ],
    [ "-tarchive_id", "string", 1, \$tarchiveID,
      "tarchive_id of the .tar to be processed from tarchive table"
    ]
); 

my $Help = <<HELP;

This script will remove the root directory from the ArchiveLocation field
in the tarchive table to make path to the tarchive relative. This should 
be used once, when updating the LORIS-MRI code.

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
          "'$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit 2;
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

################################################################
# Grep tarchive list in a hash                          ########
# %tarchive_list = {                                    ########
#      $TarchiveID => {                                 ########
#          'ArchiveLocation'    => $ArchiveLocation     ########
#          'NewArchiveLocation' => $newArchiveLocation  ########
#      }                                                ########
# };                                                    ########
################################################################
my %file_list = &getFileList( $dbh, $dataDir );

################################################################
############# Make nii files out of those minc #################
################################################################
&makeNIIAndHeader( $dbh, %file_list);


$dbh->disconnect();
print "Finished\n";
exit 0;


=pod
This function will grep all the TarchiveID and associated ArchiveLocation
present in the tarchive table and will create a hash of this information
including new ArchiveLocation to be inserted into the DB.
Input:  - $dbh = database handler
        - $dataDir = where the data (files) is located
Output: - %file_list = hash with files for a given TarchiveID
=cut
sub getFileList {

    my ($dbh, $dataDir) = @_;

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
    $sth->execute($tarchiveID);
    
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
    my ($row, $scanCategory, $destDirFinal);
    foreach $row (keys %file_list) {
        my $fileID            = $file_list{$row}{'fileID'};
        my $minc              = $file_list{$row}{'file'};
        my $fileAcqProtocolID = $file_list{$row}{'AcquisitionProtocolID'};
        my $candID            = $file_list{$row}{'candID'};
        my $visitLabel        = $file_list{$row}{'visitLabel'};
        my $mincBase          = basename($minc);
        my $remove            = $prefix . "_" . $candID . "_" . $visitLabel;  
        my $replace           = "sub-" . $candID . "_ses-" . $visitLabel ; 
        my $nifti             = $mincBase;
        $nifti                =~ s/mnc/nii/g;
        $nifti                =~ s/$remove/$replace/g;

        # for files that have DTI in their names, replace it with DWI as BIDS expects that
        $nifti                =~ s/dti/dwi/g;

        # Get the scan category (anat, func, dwi, to know which subdirectory to place files in
        ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  Scan_category
FROM
  mri_scan_type mst
WHERE
  mst.ID = ?
QUERY
        # Prepare and execute query
        my $sth = $dbh->prepare($query);
        $sth->execute($fileAcqProtocolID);
        $scanCategory = $sth->fetchrow_array();
        $destDirFinal = $destDir . "/sub-" . $candID . "/ses-" . $visitLabel . "/" . $scanCategory;
        make_path($destDirFinal) unless(-d  $destDirFinal);

        #  mnc2nii command then gzip it because BIDS expects it this way
        my $m2n_cmd = "mnc2nii -nii -quiet " .
                        $dataDir . "/" . $minc . " " .
                        $destDirFinal . "/" . $nifti;
        system($m2n_cmd);

        my $gzip_cmd = "gzip " . $destDirFinal . "/" . $nifti;
        system($gzip_cmd);

        #  create json information from minc files header; 
        # 0019:1029 is ???
        # 0018:1314 is slice timing
        my ($headerNameArr, @headerNameArr, $headerName, $headerVal, $headerFile);
        @headerNameArr   = ("repetition_time","manufacturer","manufacturer_model_name","magnetic_field_strength","device_serial_number",
                            "software_versions","acquisition:receive_coil","transmitting_coil","echo_time","inversion_time",
                            "dicom_0x0019:el_0x1029", "dicom_0x0018:el_0x1314", "institution_name");
        $headerFile      = $nifti;
        $headerFile         =~ s/nii/json/g;
        open HEADERINFO, ">$destDirFinal/$headerFile";
        HEADERINFO->autoflush(1);
        select(HEADERINFO);
        select(STDOUT);
        print HEADERINFO "{\n";
   
        foreach my $j (0..scalar(@headerNameArr)-1) {
            $headerName = $headerNameArr[$j];
            $headerName =~ s/^\"+|\"$//g;
            print "Adding now $headerName header to $headerFile\n";
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
            $sth->execute($headerName,$fileID);
            if ( $sth->rows > 0 ) {
                $headerVal = $sth->fetchrow_array();
                print HEADERINFO "$headerName: $headerVal,\n";
            }
            else {
                print "$headerName was not found for $nifti\n";
            }
        }
        print HEADERINFO "}\n";
        close HEADERINFO;
    }

}



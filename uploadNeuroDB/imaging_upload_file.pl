#! /usr/bin/perl
use strict;
use warnings;
use Carp;
use Getopt::Tabular;
use FileHandle;
use File::Basename;
use File::Temp qw/ tempdir /;
use Data::Dumper;
use FindBin;
use Cwd qw/ abs_path /;


####################TO CHECK##################################


##  Should error checking  (exit code be inside the class or the 
##  file instantiating the class

################################################################
# These are the NeuroDB modules to be used #####################
################################################################
use lib "$FindBin::Bin";

use NeuroDB::FileDecompress;

use NeuroDB::ImagingUpload;
print "asdfsafsfsafsafsa";

my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.24 $ 
                =~ /: (\d+)\.(\d+)/;
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime(time);
my $date        = sprintf(
                    "%4d-%02d-%02d %02d:%02d:%02d",
                    $year+1900,$mon+1,$mday,$hour,$min,$sec
                  );
my $debug       = 1 ;  
my $verbose     = 1;           # default for now
my $profile     = undef;       # this should never be set unless you are in a
                               # stable production environment
my $pname       = undef;       # this is the patient-name inputed by the user
                               # on the front-end

my $reckless    = 0;           # this is only for playing and testing. Don't
                               # set it to 1!!!
my $globArchiveLocation = 0;   # whether to use strict ArchiveLocation strings
                               # or to glob them (like '%Loc')
my $User             = `whoami`; 
my $template         = "ImagingUpload-$hour-$min-XXXXXX"; # for tempdir
my $TmpDir_decompressed_folder =
    tempdir($template, TMPDIR => 1, CLEANUP => 1 );
my $output = undef;
my @opt_table = (
                 ["Basic options","section"],
                 ["-profile","string",1, \$profile,
                  "name of config file in ../dicom-archive/.loris_mri"],
                 ["-patient_name","string",1, \$pname,
                  "patient-name inputed by the user on the front-end"],
                 ["Advanced options","section"],
                 ["-globLocation", "boolean", 1, \$globArchiveLocation,
                  "Loosen the validity check of the tarchive allowing for".
                  " the possibility that the tarchive was moved to a". 
                  " different directory."],
                ["Fancy options","section"]
                 );

my $Help = <<HELP;
******************************************************************************
Dicom Validator 
******************************************************************************

Author  :   
Date    :   
Version :   $versionInfo

The program does the following


- Gets the location of the uploaded file
- Unzips the uploaded file
- Source Environment
- Uses the ImagaingUpload class to :
   1) Validate the uploaded file   (set the validation to true)
   2) Run dicomtar.pl on the file  (set the dicomtar to true)
   3) Run tarchiveLoader on the file (set the minc-created to true)
   4) Move the uploaded file to the proper directory
   5) Update the mri_upload table 

HELP
my $Usage = <<USAGE;
usage: $0 </path/to/UploadedFile> [options]
       $0 -help to list options
USAGE
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;
print "asdfsafsaf";
################################################################
############### input option error checking ####################
################################################################
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ($profile && !defined @Settings::db) { 
    print "\n\tERROR: You don't have a 
    configuration file named '$profile' in:  
    $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; 
    exit 2; 
}
if (!$ARGV[0] || !$profile) { 
    print $Help; 
    print "$Usage\n\tERROR: The path to the Uploaded 
    file is not valid and an existing ".
          "profile.\n\n";  
    exit 3;  
}
if (!$pname) {
   print "$Usage\n\tERROR: The pname entered is not valid \n\n";
   exit 4;
}

$uploaded_file = abs_path($ARGV[0]);
unless (-e $uploaded_file) {
    print "\nERROR: Could not find the uploaded file
            $uploaded_file. \nPlease, make sure ".
           "the path to the uploaded file is correct. 
           Upload will exit now.\n\n\n";
    exit 5;
}

################################################################
################ Establish database connection #################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

################################################################
################ ImagingUpload  Object #########################
################################################################
my $imaging_upload = NeuroDB::ImagingUpload->new(
                  \$dbh,$uploaded_file,$patient_name);


################################################################
################ FileDecompress Object #########################
################################################################
my $file_decompress = 
    NeuroDB::FileDecompress->new($uploaded_file);

################################################################
############### Unzip File #####################################
################################################################
################################################################
my $result =  
    $file_decompress->Extract($TmpDir_decompressed_folder);

################################################################
################ Source Environment#############################
################################################################
$imaging_upload->setEnvironment();

################################################################
############### Validate File ##################################
################################################################
$is_valid = $imaging_upload->IsValid();
if (!($is_valid)) {
    $message = "\n The validation has failed";
    print $message;
    exit 6;
}
################################################################
############### Run DicomTar  ##################################
################################################################
$output = $imaging_upload->runDicomTar();
if ($output!==0) {
    $message = "\n The dicomtar execution has failed";
    print $message;
    exit 7;
}

################################################################
############### Run InsertionScripts############################
################################################################
$output = $imaging_upload->runInsertionScripts();
if ($output!==0) {
    $message = "\n The insertion scripts have failed";
    print $message;
    exit 8;
}




sub UpdateMRIUploadTable {



}

exit 0;


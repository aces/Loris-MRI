#! /usr/bin/env perl

require 5.001;
use strict;
use Getopt::Tabular;
use MNI::Startup        qw(nocputimes);
use MNI::Spawn;
use MNI::FileUtilities  qw(check_output_dirs);
use File::Basename;

# These are to load the DTI modules to be used
# use lib "$FindBin::Bin";
use DTI::DTI;

my $Usage   =   <<USAGE;

This pipeline does some pre-processing on NDN data, namely concatenating diffusion (with headers) and converting to nrrd format. 
Give a list of directories to look in and the base output dir.

Usage: $0 [options]

-help for options

USAGE
my $profile         =   undef;
my $DTIPrepVersion  =   undef;
my $notes           =   'notes';
my ($list, @args);

my @args_table      =   (["-profile",       "string",   1,      \$profile,       "name of config file in ~/.neurodb."],
                         ["-version",       "string",   1,      \$DTIPrepVersion,"DTIPrep version used if cannot be found in DTIPrep binary path"],
                         ["-list",          "string",   1,      \$list,          "file with the list of directories to look into for diffusion files (e.g. assembly/DCCID/Visit/mri/native)"    ],
                         ["-n",             "string",   1,      \$notes,         "name of notes file in each subject dir (i.e. no path)" ]
                        );

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# input option error checking
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if  ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n"; 
    exit 33;
}

if  (!$profile) {
    print "$Usage\n\tERROR: You must specify a profile.\n\n";  
    exit 33;
}

if  (!$DTIPrepVersion) {
    my  $binary =   `which DTIPrep`;
    if  ($binary=~  m/\/(DTIPrep[A-Z0-9._]+)\/DTIPrep$/i) {
        $DTIPrepVersion =   $1;
    } else {
        print "$Usage\n\t ERROR: Pipeline version could not been determined via the path to DTIPrep binary. You need to specify which version of DTIPrep you will be using with -version option.";  
        exit 33;
    }
}

# These settings are in a config file (profile)
my  $data_dir       =   $Settings::data_dir;
my  $t1_scan_type   =   $Settings::t1_scan_type;
my  $DTI_volumes    =   $Settings::DTI_volumes;
my  $reject_thresh  =   $Settings::reject_thresh;
my  $bcheck_prot    =   $Settings::bcheck_prot;
my  $nobcheck_prot  =   $Settings::nobcheck_prot;

# needed for log file
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)   =   localtime(time);
my  $date   =   sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log    =   $data_dir . "/logs/DTIPrep_pipeline/DTI_QC" . $date . ".log";
open(LOG,">>$log");
print LOG "Log file, $date\n";
print LOG "DTIPrep version: $DTIPrepVersion\n\n";

# determine DTIPrep output directory
my $outdir  =   $data_dir . "/pipelines/DTIPrep/" . $DTIPrepVersion;

# parse through list of directories containing DTI data (i.e. $data_dir/assembly/DCCID/Visit/mri/native)
open(DIRS,"<$list");
my  @dirs   =   <DIRS>;
close(DIRS);
foreach my $d (@dirs)   {
    chomp ($d);

    ####### Step 1: Get Site, SubjectID and Visit #######
    my  ($site, $subjID, $visit)    =   &Settings::get_DTI_Site_CandID_Visit($d); 
    if  ((!$site) || (!$subjID) || (!$visit))  {
        print LOG "\n#############################\n";
        print LOG "\n#############################\n";
        print LOG "\nERROR:Cannot find site,ID,visit for $d\n";
        next;
    }else{
        print LOG "\n################################\n";
        print LOG "SITE". "\t" . "subID" . "\t" . "visit". "\n";
        print LOG $site . "\t" . $subjID . "\t" . $visit . "\n";
        print LOG "--------------------------------\n";
        print     $site . "\t" . $subjID . "\t" . $visit . "\n";
    }

    ####### Step 2: Create output folders #######
        ## for nobcheck_protocol ##
    my ($nobcheckQC_out)=   DTI::createOutputFolders($outdir,
                                                     $subjID, 
                                                     $visit, 
                                                     $nobcheck_prot);
        ## for bcheck_protocol ##
    my ($bcheckQC_out)  =   DTI::createOutputFolders($outdir,
                                                     $subjID, 
                                                     $visit, 
                                                     $bcheck_prot);
    
    ####### Step 3: Get files to process #######
    # Get anatomical and DTI files. Concatenate multiple DTI files if DTI acquisition performed with several scans.
    my  ($anat,$files)  =   DTI::getFiles($d, 
                                          $nobcheckQC_out, 
                                          $site, 
                                          $subjID, 
                                          $visit, 
                                          $t1_scan_type, 
                                          $DTI_volumes);
    if  (@$files    ==  0)  {

        print LOG "\nWARNING: Could not find DTI files with $DTI_volumes volumes for: " . 
                  $site . "_" . $subjID . "_" . $visit . "\n\n\n";
        next;

    } elsif (@$files == 1)  {           # if one $files contain only one DTI file

        my $dti_file    =   @$files[0]; # fetch file path in array $files
        print $dti_file . "\n";
        print LOG "==> Found anat file:         $anat\n";
        print LOG "==> Found DTI  file:         $dti_file\n";

    ####### Step 4: Run DTIPrep without bcheck option #######
        print LOG "==> DTIPrep protocol used:   $nobcheck_prot\n";
        my ($QCed_minc, $QC_report, $insert_hdr)    =   DTI::runQCtools($dti_file,
                                                                        $data_dir,
                                                                        $nobcheckQC_out,
                                                                        $nobcheck_prot,
                                                                        $DTIPrepVersion);
        if  ((-e $QCed_minc) && ($QC_report)) {
            print LOG "==> nobcheck QCed minc is:   $QCed_minc\n" .
                      "==> nobcheck QC report is:   $QC_report\n" ;
        } else {
            print LOG "\n\n--- DIE --- nobcheck QCed MINC OR/AND QC report WERE NOT CREATED --- \n";
        }
        if  (!($insert_hdr)) { 
            print LOG "\n\n--- DIE WHEN INSERTING ARGUMENTS TO nobcheck QCed MINC HEADER --- \n" . 
                      "Number of arguments not equal to number of values to insert in QCed minc header.\n\n";
        }
    
    ####### Step 5: Run DTIPrep with bcheck option (Stringent DTIPrep protocol) #######
        print LOG "==> DTIPrep protocol used:   $bcheck_prot\n";
        my ($bcheckQCed_minc, $bcheckQC_report, $bcheck_insert_hdr) =   DTI::runQCtools($dti_file,
                                                                                        $data_dir,
                                                                                        $bcheckQC_out,
                                                                                        $bcheck_prot,
                                                                                        $DTIPrepVersion);
        if  ((-e $bcheckQCed_minc) && ($bcheckQC_report)) {
            print LOG "==> bcheck QCed minc is:     $QCed_minc\n" .
                      "==> bcheck QC report is:     $QC_report\n" ;
        } else {
            print LOG "\n\n--- DIE --- bcheck QCed MINC OR/AND QC report WERE NOT CREATED --- \n";
        }
        if (!($bcheck_insert_hdr)) {
            print LOG "\n\n--- DIE WHEN INSERTING ARGUMENTS TO bcheck QCed MINC HEADER --- \n" . 
                      "Number of arguments not equal to number of values to insert in QCed minc header.\n\n";
        }
                                                      
    ####### Step 6: Create FA and RGB maps for non stringent protocol (i.e. nobcheck) #######
        my ($FA, $RGB, $rgb_pic);
        if (-e $QCed_minc){
            my $success;
            ($success, $FA, $RGB, $rgb_pic) =   DTI::create_FA_RGB_maps($QCed_minc,
                                                                        $anat,
                                                                        $nobcheckQC_out);
            if ($success eq "yes") {
                print "FA and RGB successfully created!!";
                print LOG "==> FA and RGB maps successfully created!!\n" .
                          "FA map is:       $FA\n" .
                          "RGB map is:      $RGB\n";
                my  ($FA_insert_hdr)    =   DTI::insertMincHeader($dti_file, 
                                                                  $FA,  
                                                                  $QC_report, 
                                                                  $DTIPrepVersion);
                if (!($FA_insert_hdr)) {
                    print LOG "\n\n--- DIE WHEN INSERTING ARGUMENTS TO FA QCed MINC HEADER --- \n" .
                              "Number of arguments not equal to number of values to insert in FA QCed minc header.\n\n";
                }
                my  ($RGB_insert_hdr)   =   DTI::insertMincHeader($dti_file, 
                                                                  $RGB, 
                                                                  $QC_report, 
                                                                  $DTIPrepVersion);
                if (!($RGB_insert_hdr)) {
                    print LOG "\n\n--- DIE WHEN INSERTING ARGUMENTS TO RGB QCed MINC HEADER --- \n" .
                              "Number of arguments not equal to number of values to insert in RGB QCed minc header.\n\n";
                }
            } elsif ($success ==  0)  {   
                print LOG "\n\n*** FA and RGB maps already created ***\n\n";
                print     "\n\n*** FA and RGB maps already created ***\n\n";
            } elsif ($success ==  1)  {   
                print LOG "\n\n*** Anat file $anat or DTI file $QCed_minc does not exist... ***\n\n";
                print     "\n\n*** Anat file $anat or DTI file $QCed_minc does not exist... ***\n\n";
            } elsif ($success ==  2)  {   
                print LOG "\n\n*** Anatomical mask or preprocessed DTI does not exist... ***\n\n";
                print     "\n\n*** Anatomical mask or preprocessed DTI does not exist... ***\n\n";
            } elsif ($success ==  3)  {   
                print LOG "\n\n*** RGB map $RGB does not exist... ***\n\n";
                print     "\n\n*** RGB map $RGB does not exist... ***\n\n";
            } else                    {   
                print LOG "This should never happen...";
                print     "This should never happen...";
            }

            # Create a default notes file for QC summary and manual notes
            my $note_file   =   $nobcheckQC_out."/".$notes;
            DTI::createNoteFile($nobcheckQC_out, $note_file, $QC_report, $reject_thresh)  unless (-e $note_file);
        }
    } else {
        print LOG "---DIED--- more than one DTI acquisition was found for: ".$site."_".$subjID."_".$visit.". \n\n\n";   
        next;
    }
}

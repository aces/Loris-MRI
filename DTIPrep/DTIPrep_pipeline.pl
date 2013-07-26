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

Need to write up description once pipeline over.
DTIPrep will be run twice, once with gradient check to see which direction shows a lot of movement and once without gradient check (the one that will be registered into the DB).

Usage: $0 [options]

-help for options

USAGE
my $profile         = undef;
my $concat          = 0;
my $DTIPrepVersion  = undef;
my $runDTIPrep      = 0;
my $DTIPrepProtocol = "";
my $notes           = 'notes';
my ($list, @args);

my @args_table      = (["-profile",        "string",   1,      \$profile,        "name of config file in ~/.neurodb."                            ],
                       ["-list",           "string",   1,      \$list,           "file with the list of directories to look into for diffusion files (e.g. assembly/DCCID/Visit/mri/native)."    ],
                       ["-concat",         "boolean",   1,      \$concat,         "specify this option if you need to concatenate several DTI scans to obtain a complete DTI dataset. Note that you would need to a function in your config file to concatenate the DTIs."    ],
                       ["-DTIPrepVersion", "string",   1,      \$DTIPrepVersion, "DTIPrep version used if cannot be found in DTIPrep binary path."],
                       ["-runDTIPrep",     "boolean",  1,      \$runDTIPrep,     "if set, run DTIPrep tool on raw DTI data."                      ],
                       ["-DTIPrepProtocol","string",   1,      \$DTIPrepProtocol,"DTIPrep protocol to use or that was used to run DTIPrep."],
                       ["-n",              "string",   1,      \$notes,          "name of notes file in each subject dir (i.e. no path)."         ]
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
my  @nativedirs   =   <DIRS>;
close(DIRS);
foreach my $nativedir (@nativedirs)   {
    chomp ($nativedir);

    ####### Step 1: get Site, SubjectID and Visit
    my ($site, $subjID, $visit) = &Settings::get_DTI_Site_CandID_Visit($nativedir); 
    if ((!$site) || (!$subjID) || (!$visit))  {
        print LOG "\n#############################\n";
        print LOG "\nWARNING:Cannot find site,ID,visit for $nativedir\n";
        print LOG "\n#############################\n";
        next;
    }else{
        print LOG "\n################################\n";
        print LOG "SITE". "\t" . "subID" . "\t" . "visit". "\n";
        print LOG $site . "\t" . $subjID . "\t" . $visit . "\n";
        print LOG "--------------------------------\n";
        print     $site . "\t" . $subjID . "\t" . $visit . "\n";
    }

    ####### Step 2: - if $runDTIPrep is set,     create out directories. 
    #######         - if $runDTIPrep is not set, fetche out directories.
    my ($QCoutdir)  = DTI::createOutputFolders($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep);
    if (!$QCoutdir) {
        my $verb_message = "create" if ($runDTIPrep );
        my $verb_message = "find"   if (!$runDTIPrep);
        print LOG "\n#############################\n";
        print LOG "\nWARNING:Could not $verb_message QC out directory in $outdir for candidate $subjID, visit $visit and DTIPrep protocol $DTIPrepProtocol. \n";
        print LOG "\n#############################\n";
        next;
    } else {
        print LOG "DTIPrep out directory: " . $QCoutdir . "\n";
        print LOG "--------------------------------\n";
    }

    ####### Step 3: - get raw DTI file to process (later may need to develop concatenation of several DTI files into one dataset when a DTI dataset is acquired in several smaller DTI scans). 
    #######         - & determine output names based on raw DTI file names and organize them into a hash. 
    my ($DTIs_list)    = DTI::getRawDTIFiles($nativedir, $DTI_volumes);   
    if  (@$DTIs_list == 0) {
        print LOG "\n#############################\n";
        print LOG "\nWARNING: Could not find DTI files with $DTI_volumes volumes for in $nativedir.\n";
        print LOG "\n#############################\n";
        next;
    }
    ## Create a hash with raw dti as first level key, processed file type as second level key and processed file names as values. See example:
    #   dti_file_1  -> Raw_nrrd     => outputname
    #               -> QCed_nrrd    => outputname etc... (QCTxtReport, QCXmlReport, QCed_minc, QCProt)
    #   dti_file_2  -> Raw_nrrd     => outputname etc...
    my ($DTIrefs)   = DTI::createDTIhashref($DTIs_list, $QCoutdir, $DTIPrepProtocol); 


    ####### Step 4: - if $runDTIPrep is set,     run processing pipeline (with & without bcheck option). The processing pipeline will convert mnc2nrrd and run DTIPrep. 
    &processingPipeline($DTIs_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol) if ($runDTIPrep);
    exit;
### Good so far !!!####

    ####### Check if all output exists before running what's left!

    ####### Step 5: nrrd2mnc conversion and mincheader reinsertion

    ####### Step 5: create FA and RGB maps for non stringent protocol (i.e. nobcheck) #######
#        my ($FA, $RGB, $rgb_pic);
#        if (-e $QCed_minc){
#            my $success;
#            ($success, $FA, $RGB, $rgb_pic) =   DTI::create_FA_RGB_maps($QCed_minc, $anat, $nobcheckQC_out);
#            if ($success eq "yes") {
##                print "FA and RGB successfully created!!";
#                print LOG "==> FA and RGB maps successfully created!!\n" .
#                          "FA map is:       $FA\n" .
#                          "RGB map is:      $RGB\n";
#                my  ($FA_insert_hdr)    =   DTI::insertMincHeader($dti_file, $data_dir, $FA, $QC_report, $DTIPrepVersion);
#                if (!($FA_insert_hdr)) {
#                    print LOG "\n\n--- DIE WHEN INSERTING ARGUMENTS TO FA QCed MINC HEADER --- \n" .
#                              "Number of arguments not equal to number of values to insert in FA QCed minc header.\n\n";
#                }
#                my  ($RGB_insert_hdr)   =   DTI::insertMincHeader($dti_file, $data_dir, $RGB, $QC_report, $DTIPrepVersion);
#                if (!($RGB_insert_hdr)) {
#                    print LOG "\n\n--- DIE WHEN INSERTING ARGUMENTS TO RGB QCed MINC HEADER --- \n" .
#                              "Number of arguments not equal to number of values to insert in RGB QCed minc header.\n\n";
#                }
#            } elsif ($success ==  0)  {   
#                print LOG "\n\n*** FA and RGB maps already created ***\n\n";
##                print     "\n\n*** FA and RGB maps already created ***\n\n";
##            } elsif ($success ==  1)  {   
#                print LOG "\n\n*** Anat file $anat or DTI file $QCed_minc does not exist... ***\n\n";
#                print     "\n\n*** Anat file $anat or DTI file $QCed_minc does not exist... ***\n\n";
#            } elsif ($success ==  2)  {   
#                print LOG "\n\n*** Anatomical mask or preprocessed DTI does not exist... ***\n\n";
#                print     "\n\n*** Anatomical mask or preprocessed DTI does not exist... ***\n\n";
#            } elsif ($success ==  3)  {   
#                print LOG "\n\n*** RGB map $RGB does not exist... ***\n\n";
#                print     "\n\n*** RGB map $RGB does not exist... ***\n\n";
#            } else                    {   
#                print LOG "This should never happen...";
#                print     "This should never happen...";
#            }
#
#            # Create a default notes file for QC summary and manual notes
#            my $note_file   =   $nobcheckQC_out."/".$notes;
#            DTI::createNoteFile($nobcheckQC_out, $note_file, $QC_report, $reject_thresh)  unless (-e $note_file);
#        }
}


###############
## Functions ##
###############


=pod
Function that creates the output folders, get the raw DTI files, convert them to nrrd and run DTIPrep using a bcheck protocol and a nobcheck protocol.
=cut
sub processingPipeline {
    my ($DTIs_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol)  = @_;

    foreach my $dti_file (@$DTIs_list) {

        my $raw_nrrd    = $DTIrefs->{$dti_file}{'Raw_nrrd'};
        my $QCed_nrrd   = $DTIrefs->{$dti_file}{'QCed_nrrd'};
        my $QCProt      = $DTIrefs->{$dti_file}{'QCProt'};

        my ($convert_status, $DTIPrep_status, $copyProt_status);
        if (-e $raw_nrrd) {
            print LOG "Raw DTI already converted to nrrd.\n";
        } else {
            ($convert_status)   = DTI::convert_DTI($dti_file, $raw_nrrd, '--short --minc-to-nrrd');
            print LOG "Raw DTI successfully converted to nrrd!\n"   if ($convert_status);
            print LOG "ERROR: Raw DTI mnc2nrrd conversion failed!\n"       if (!$convert_status);
        }

        if (-e $QCed_nrrd) {
            print LOG "QCed nrrd file already exists (DTIPrep was already run).\n";
        } else {
            ($DTIPrep_status)   = DTI::runDTIPrep($raw_nrrd, $DTIPrepProtocol, $QCed_nrrd)    if (-e $raw_nrrd);
            print LOG "DTIPrep was successfully run. QCed nrrd is $QCed_nrrd.\n"    if ($DTIPrep_status);
            print LOG "ERROR: DTIPrep failed. \n"  if (!$DTIPrep_status);
        }

        if (-e $QCProt) {
            print LOG "DTIPrep protocol was already copied in output directory $QCoutdir.\n";
        } else {
            ($copyProt_status)  = DTI::copyDTIPrepProtocol($DTIPrepProtocol, $QCProt);
            print LOG "DTIPrep protocol successfully copied in output directory $QCoutdir.\n"   if ($copyProt_status);
            print LOG "ERROR: Failed to copy DTIPrep protocol in output directory. \n\t Protocol to copy is: $DTIPrepProtocol. \n\tOutput directory is $QCoutdir.\n"   if (!$copyProt_status);
        }
    }
}                                                  

#    foreach my $dti_file (@$DTIs_list) {
#        print "DTI file: $dti_file\n";
#        print "DTI raw nrrd: $DTIrefs->{$dti_file}{'Raw_nrrd'}\n";
#        print "DTI QCed nrrd: $DTIrefs->{$dti_file}{'QCed_nrrd'}\n";
#        print "DTI QCProt: $DTIrefs->{$dti_file}{'QCProt'}\n";
#        print "DTI QCTxtReport: $DTIrefs->{$dti_file}{'QCTxtReport'}\n";
#        print "DTI QCXmlReport: $DTIrefs{$dti_file}{'QCXmlReport'}\n";
#        print "DTI QCed minc: $DTIrefs{$dti_file}{'QCed_minc'}\n";
#    }

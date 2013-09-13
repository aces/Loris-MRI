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

NEED TO WRITE UP DESCRIPTION ONCE PIPELINE OVER.

DTIPrep_pipeline can be used to run DTIPrep on raw DTI datasets stored in native folder and convert outputs back to minc, create QC report and RGB maps to finally register them in the database. 
If the option -runDTIPrep is not set, it will skip the DTIPrep processing portion of the pipeline and fetch DTIPrep outputs based on the DTIPrep protocol name that was used to create them and convert the outputs to minc etc...

This pipeline will:
    - get the raw DTI file in the native from the list given as input (-list option)
    - create (or fetch if -runDTIPrep not set) output directories based on DTIPrep version and protocol
    - convert raw minc file to nrrd and run DTIPrep if -runDTIPrep is set
    - fetch DTIPrep outputs (QCed.nrrd, QCReport.txt, QCXMLResults.xml and protocol.xml)
    - convert QCed.nrrd back to minc with all the header information (based on native minc)
    - create FA and RGB maps with all the header information
    - register the files in the database

Usage: $0 [options]

-help for options

USAGE
my $profile         = undef;
my $concat          = 0;
my $DTIPrepVersion  = undef;
my $runDTIPrep      = 0;
my $DTIPrepProtocol = undef;
my $notes           = 'notes';
my ($list, @args);

my @args_table      = (["-profile",        "string",   1,      \$profile,        "name of config file in ~/.neurodb."                            ],
                       ["-list",           "string",   1,      \$list,           "file with the list of raw diffusion files (in assembly/DCCID/Visit/mri/native)."    ],
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
if ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n"; 
    exit 33;
}

if (!$profile) {
    print "$Usage\n\tERROR: You must specify a profile.\n\n";  
    exit 33;
}

if (!$DTIPrepVersion) {
    my  $binary =   `which DTIPrep`;
    if  ($binary=~  m/\/(DTIPrep[A-Z0-9._]+)\/DTIPrep$/i) {
        $DTIPrepVersion =   $1;
    } else {
        print "$Usage\n\t ERROR: Pipeline version could not been determined via the path to DTIPrep binary. You need to specify which version of DTIPrep you will be using with -version option.\n\n";  
        exit 33;
    }
}

if (!$DTIPrepProtocol) {
    print "$Usage\n\tERROR: You need to specify a DTIPrep protocol to run DTIPrep or that was used to run DTIPrep.\n\n";
    exit 33;
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
    
    #######################
    ####### Step 1: #######  Get Site, SubjectID and Visit label
    #######################
    my ($site, $subjID, $visit) = &getIdentifiers($nativedir);
    next if ((!$site) || (!$subjID) || !($visit));

    #######################
    ####### Step 2: ####### - If $runDTIPrep is set,     create out directories. 
    ####################### - If $runDTIPrep is not set, fetche out directories.
    my ($QCoutdir)  = &getOutputDirectories($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep);
    next if (!$QCoutdir);

    #######################
    ####### Step 3: ####### - Get raw DTI file to process (later may need to develop concatenation of several DTI files into one dataset when a DTI dataset is acquired in several smaller DTI scans). 
    ####################### - & determine output names based on raw DTI file names and organize them into a hash ($DTIrefs). 
    my ($DTIs_list, $DTIrefs)   = &fetchData($nativedir, $DTI_volumes, $t1_scan_type, $QCoutdir, $DTIPrepProtocol);
    next if ((!$DTIs_list) || (!$DTIrefs));

    #######################
    ####### Step 4: ####### - Run preprocessing pipeline (mnc2nrrd + DTIPrep) if $runDTIPrep is set. 
    #######################
    &preprocessingPipeline($DTIs_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol) if ($runDTIPrep);

    #######################
    ####### Step 5: ####### Run post processing pipeline: 
    #######################    - will convert QCed file to minc
    #                          - will insert mincheader information from raw DTI into QCed minc DTI
    #                          - will create FA and RGB maps
    my ($post_success)  = &postProcessingPipeline($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion);
    next if (!$post_success);

    #######################
    ####### Step 6: ####### Create FA and RGB maps
    #######################
    

}

###############
## Functions ##
###############

=pod
Fetches site, candID and visit label from the native directory given in input.
Will return undef if could not find the site, candID or the visit label.
Will return the site, candID and visit label if they exist.
Relevant information will also be printed in the log file.
=cut
sub getIdentifiers {
    my ($nativedir) = @_;    

    my ($site, $subjID, $visit) = &Settings::get_DTI_Site_CandID_Visit($nativedir); 
    if ((!$site) || (!$subjID) || (!$visit))  {
        print LOG "\n#############################\n";
        print LOG "\nWARNING:Cannot find site,ID,visit for $nativedir\n";
        print LOG "\n#############################\n";
        return undef;
    }else{
        print LOG "\n################################\n";
        print LOG "SITE". "\t" . "subID" . "\t" . "visit". "\n";
        print LOG $site . "\t" . $subjID . "\t" . $visit . "\n";
        print LOG "--------------------------------\n";
        print     $site . "\t" . $subjID . "\t" . $visit . "\n";
        return ($site, $subjID, $visit);
    }
}

=pod
Determine pipeline output directory, based on the root outdir, DTIPrep protocol, candID and visit label:
(outdir/ProtocolName/CandID/VisitLabel).
If $runDTIPrep is set, the function will create the output folders.
If $runDTIPrep is not set, will check that the directory exists.
=cut
sub getOutputDirectories {
    my ($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep)    = @_;    

    my ($QCoutdir)  = DTI::createOutputFolders($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep);
    if (!$QCoutdir) {
        my $verb_message = "create" if ($runDTIPrep );
        my $verb_message = "find"   if (!$runDTIPrep);
        print LOG "\n#############################\n";
        print LOG "\nWARNING:Could not $verb_message QC out directory in $outdir for candidate $subjID, visit $visit and DTIPrep protocol $DTIPrepProtocol. \n";
        print LOG "\n#############################\n";
        return undef;
    } else {
        print LOG "DTIPrep out directory: " . $QCoutdir . "\n";
        print LOG "--------------------------------\n";
        return ($QCoutdir);
    }
}

=pod
Fetch the raw DTIs and foreach DTI, determine output names and store them into a hash ($DTIrefs).
Will return undef if could not find any raw DTI dataset. 
Will return the list of raw DTIs found and a hash with the preprocessing output names.
Will also print relevant information in the log file.
=cut
sub fetchData {
    my ($nativedir, $DTI_volumes, $t1_scan_type, $QCoutdir, $DTIPrepProtocol)  = @_;

    # Get DTI datasets
    my ($DTIs_list)    = DTI::getRawDTIFiles($nativedir, $DTI_volumes);   
    if  (@$DTIs_list == 0) {
        print LOG "\n#############################\n";
        print LOG "\nWARNING: Could not find DTI files with $DTI_volumes volumes for in $nativedir.\n";
        print LOG "\n#############################\n";
        return undef;
    }

    # Get anatomical data
    my ($anat)  = DTI::getAnatFile($nativedir, $t1_scan_type);

    ## Create a hash with raw dti as first level key, processed file type as second level key and processed file names as values. See example:
    #   dti_file_1  -> Raw_nrrd     => outputname
    #               -> QCed_nrrd    => outputname etc... (QCTxtReport, QCXmlReport, QCed_minc, QCProt)
    #   dti_file_2  -> Raw_nrrd     => outputname etc...
    my ($DTIrefs)   = DTI::createDTIhashref($DTIs_list, $anat, $QCoutdir, $DTIPrepProtocol); 

    return ($DTIs_list, $DTIrefs);
}

=pod
Function that creates the output folders, get the raw DTI files, convert them to nrrd and run DTIPrep using a bcheck protocol and a nobcheck protocol.
=cut
sub preprocessingPipeline {
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

=pod
Check if all Preprocessing DTIPrep files are in the output folder.
They should include: - QCed nrrd file
                     - DTIPrep QC text report
                     - DTIPrep QC xml report
                     - & a copy of the protocol used to run DTIPrep (QCProt)
Will return 1 if all output files could be found, undef if at least one output file is missing. Relevant information will also be printed in the log file.
=cut
sub checkPreprocessOutputs {
    my ($dti_file, $DTIrefs, $QCoutdir, $DTIPrepProtocol)  = @_;

    my $QCed_nrrd   = $DTIrefs->{$dti_file}{'QCed_nrrd'};
    my $QCTxtReport = $DTIrefs->{$dti_file}{'QCTxtReport'};
    my $QCXmlReport = $DTIrefs->{$dti_file}{'QCXmlReport'};
    my $QCProt      = $DTIrefs->{$dti_file}{'QCProt'};

    if ((-e $QCed_nrrd) && (-e $QCTxtReport) && (-e $QCXmlReport) && (-e $QCProt)) {
        print LOG "All DTIPrep preprocessing outputs were found in $outdir.\n";
        return $QCTxtReport;
    } else {
        print LOG "\nERROR: Could not find all DTIPrep preprocessing outputs in $outdir.\n" .
                    "\tQCed nrrd:   $QCed_nrrd\n"   .
                    "\tQCTxtReport: $QCTxtReport\n" .
                    "\tQCXmlReport: $QCXmlReport"   .
                    "\tQCProt:      $QCProt\n"      ;
        return undef;
    }
}    


sub convert2mnc {
    my ($dti_file, $DTIrefs, $data_dir, $DTIPrepVersion)   = @_;

    my $QCed_nrrd   = $DTIrefs->{$dti_file}{'QCed_nrrd'};
    my $QCed_minc   = $DTIrefs->{$dti_file}{'QCed_minc'};
    my $QCTxtReport = $DTIrefs->{$dti_file}{'QCTxtReport'};

    # Convert QCed nrrd file back into minc file (with updated header)
    my  ($insert_header, $convert_status);
    if  (-e $QCed_nrrd) {
        if (-e $QCed_minc) {
            print LOG "QCed minc already exists.\n";
        } else {
            # convert QCed file to minc
            ($convert_status)   = DTI::convert_DTI($QCed_nrrd, $QCed_minc, '--nrrd-to-minc');
            # insert mincheader fields stored in raw dti_file (aside from the fields with direction information) into QCed minc file
            ($insert_header)    = DTI::insertMincHeader($dti_file, $data_dir, $QCed_minc, $QCTxtReport, $DTIPrepVersion);
        }
    }
    
    if ($convert_status) {
        print LOG "QCed DTI successfully converted to minc.\n";
        return 1;
    } else {
        return undef;
    }
}

=pod
Post processing pipeline will:
    - check that all preprocessing outputs are available
    - convert QCed nrrd file to minc and insert header informations
    - run post-processing that will create FA and RGB maps and insert mincheader information
=cut
sub postProcessingPipeline {
    my ($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion)  = @_;    

    my ($convert_status, $postproc_status);
    foreach my $dti_file (@$DTIs_list) {

        # Check if all DTIPrep preprocessing outputs are available
        my ($QCTxtReport)       = &checkPreprocessOutputs($dti_file, $DTIrefs, $QCoutdir, $DTIPrepProtocol);
        return undef    if (!$QCTxtReport);  

        # Convert QCed_nrrd DTI to minc   
        ($convert_status)    = &convert2mnc($dti_file, $DTIrefs, $data_dir, $DTIPrepVersion);
        # Create FA and RGB maps
        ($postproc_status)   = &runPostProcessing($dti_file, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepVersion);

        # Create a default notes file for QC summary and manual notes
        my $note_file   =   $QCoutdir."/".$notes;
        DTI::createNoteFile($QCoutdir, $note_file, $QCTxtReport, $reject_thresh)  unless (-e $note_file);

    }
#### return part still need to be worked out
    if ($convert_status && $postproc_status) {
        return 1;
    } else {
        return undef;
    }
}

=pod
Will create FA and RGB map + insert mincheader information.
=cut
sub runPostProcessing {
    my ($dti_file, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepVersion) = @_;

    # Initialize variables
    my $QCed_minc   = $DTIrefs->{$dti_file}{'QCed_minc'};
    my $QCTxtReport = $DTIrefs->{$dti_file}{'QCTxtReport'};
    my $FA          = $DTIrefs->{$dti_file}{'FA'};
    my $RGB         = $DTIrefs->{$dti_file}{'RGB'};
    my ($postProc_success, $FA_insert, $RGB_insert);

    # If QCed minc file does not exist, print LOG and stop
    unless (-e $QCed_minc) { 
       print LOG "ERROR: could not find QCed minc DTI file.\n";
       return undef;
    }

    # Create FA and RGB maps
    ($postProc_success) = DTI::create_FA_RGB_maps($dti_file, $DTIrefs, $QCoutdir);

    # If FA and RGB were successfully created, insert mincheader information
    if ($postProc_success eq "yes") {
        print LOG "==> FA and RGB maps successfully created!!\n  FA map:\t$FA\n  RGB map:\t $RGB\n";

        # Insert mincheader information into FA minc
        ($FA_insert)    =   DTI::insertMincHeader($dti_file, $data_dir, $FA, $QCTxtReport, $DTIPrepVersion);

        # Insert mincheader information into RGB minc
        ($RGB_insert)   =   DTI::insertMincHeader($dti_file, $data_dir, $RGB, $QCTxtReport, $DTIPrepVersion);
    }

    # Print in LOG file
    if ($postProc_success == 0)    { print LOG "FA and RGB maps already created\n";                }
    elsif ($postProc_success == 1) { print LOG "ERROR: anat or QCed minc not found in $QCoutdir\n\n";} 
    elsif ($postProc_success == 2) { print LOG "ERROR: preprocessed anat or QCed dti not found in $QCoutdir\n\n";}
    elsif ($postProc_success == 3) { print LOG "ERROR: RGB map not found in $QCoutdir\n\n";   }

    if (!$FA_insert)  { print LOG "ERROR: FA mincheader insertion failed: # arguments != # values to insert.\n\n"; }
    if (!$RGB_insert) { print LOG "ERROR: RGB mincheader insertion failed: # arguments != # values to insert.\n\n"; }

    # Return 1 if map already existed or if FA and RBG map successfully created. Return undef otherwise.
    if (($postProc_success == 0) || (($FA_insert) && ($RGB_insert))) {
        return 1;
    } else {
        return undef;
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


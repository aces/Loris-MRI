#! /usr/bin/env perl

require 5.001;
use strict;
use Getopt::Tabular;
use MNI::Startup        qw(nocputimes);
use MNI::Spawn;
use MNI::FileUtilities  qw(check_output_dirs);
use File::Basename;
use XML::Simple;

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
my $DTIPrepVersion  = undef;
my $runDTIPrep      = 0;
my $DTIPrepProtocol = undef;
my $runMincdiffusion= 0;
my $notes           = 'notes';
my ($list, @args);

my @args_table      = (["-profile",         "string",   1,      \$profile,          "name of config file in ~/.neurodb."                             ],
                       ["-list",            "string",   1,      \$list,             "file with the list of raw diffusion files (in assembly/DCCID/Visit/mri/native)."    ],
                       ["-DTIPrepVersion",  "string",   1,      \$DTIPrepVersion,   "DTIPrep version used if cannot be found in DTIPrep binary path."],
                       ["-runDTIPrep",      "boolean",  1,      \$runDTIPrep,       "if set, run DTIPrep tool on raw DTI data."                      ],
                       ["-DTIPrepProtocol", "string",   1,      \$DTIPrepProtocol,  "DTIPrep protocol to use or that was used to run DTIPrep."       ],
                       ["-n",              "string",    1,      \$notes,            "name of notes file in each subject dir (i.e. no path)."         ],
                       ["-runMincdiffusion","boolean",  1,      \$runMincdiffusion, "if set, run mincdiffusion tools on QCed DTI dataset."           ]
                      );

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# input option error checking
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named \"$profile\" in:  $ENV{HOME}/.neurodb/ \n\n"; 
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
my  $niak_path      =   $Settings::niak_path;
my  $QCed2_step     =   $Settings::QCed2_step;

# Exit program if runMincdiffusion is set and $niak_path is not set as minctensor needs Niak to run
if  (($runMincdiffusion == 1) && (!$niak_path)) {
    print "$Usage\n\tERROR: variable niak_path need to be set in the config file if -runMincdiffusion is set.\n\n";
    exit 33;
}

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
    ####### Step 3: ####### - Read DTIPrep XML protocol (will help to determine output names). 
    #######################
    my ($protXMLrefs)        = &DTI::readDTIPrepXMLprot($DTIPrepProtocol);
    next if (!$protXMLrefs);

    #######################
    ####### Step 4: ####### - Get raw DTI file to process (later may need to develop concatenation of several DTI files into one dataset when a DTI dataset is acquired in several smaller DTI scans). 
    ####################### - & determine output names based on raw DTI file names and organize them into a hash ($DTIrefs). 
    my ($DTIs_list, $DTIrefs)= &fetchData($nativedir, $DTI_volumes, $t1_scan_type, $QCoutdir, $DTIPrepProtocol, $protXMLrefs, $QCed2_step);
    next if ((!$DTIs_list) || (!$DTIrefs));

    #######################
    ####### Step 5: ####### - Run preprocessing pipeline (mnc2nrrd + DTIPrep) if $runDTIPrep is set. 
    #######################
    if ($runDTIPrep) {
        my ($pre_success)   = &preprocessingPipeline($DTIs_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol);
        # if no preprocessing pipeline was successful for this visit, go to the next one.
        next if (!$pre_success);
    } else {
        print LOG "DTIPrep won't be run on this dataset. (-runDTIPrep option was not set)\n";
        print LOG "--------------------------------\n";
    }

    #######################
    ####### Step 6: ####### Check if DTIPrep outputs are available and will convert nrrd files to mnc. 
    ####################### These outputs are:
    #                          - QCed.nrrd
    #                          - QCReport.txt
    #                          - XMLQCResult.xml
    my ($convert_success)   = &check_and_convertPreprocessedFiles($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion);
    # if no preprocessed files were found or conversion was not successful for this visit, go to the next one.
    next if (!$convert_success);

    #######################
    ####### Step 7: ####### Run post processing pipeline: 
    #######################    - will convert QCed file to minc
    #                          - will insert mincheader information from raw DTI into QCed minc DTI
    #                          - will create FA and RGB maps
    if ($runMincdiffusion) {
        my ($post_success)  = &mincdiffusionPipeline($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion, $niak_path);
        next if (!$post_success);
    } else {
        print LOG "mincdiffusion tools won't be run for this dataset. (-runMincdiffusion option was not set)\n";
        print LOG "--------------------------------\n";
        exit;
    }

    #######################
    ####### Step 8: ####### Register files into the DB
    #######################
    

}

exit 0;


        # Create a default notes file for QC summary and manual notes
 #       my $note_file   =   $QCoutdir."/".$notes;
#        DTI::createNoteFile($QCoutdir, $note_file, $QCTxtReport, $reject_thresh)  unless (-e $note_file);










###############
## Functions ##
###############

=pod
Fetches site, candID and visit label from the native directory of the dataset to process.
Input:  - $nativedir: native directory of the dataset to process
Output: - undef if could not find the site, candID or visit label.
        - $site, $candID and $visit_label informations if they were found.
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
Determine pipeline's output directory, based on the root outdir, DTIPrep protocol, candID and visit label: (outdir/ProtocolName/CandID/VisitLabel).
If $runDTIPrep is defined, the function will create the output folders.
If $runDTIPrep is not defined, will check that the directory exists.

- Inputs: -$outdir  = output directory where DTIPrep results for all datasets for all subjects will be stored (in /data/project/data/pipelines/DTIPrep/DTIPrep_version)
          - $subjID = candidate ID of the DTI dataset to be processed
          - $visit  = visit label of the DTI dataset to be processed
          - $DTIPrepProtocol= XML file with the DTIPrep protocol to be used for analyses
          - $runDTIPrep = a boolean which will determine if OutputFolders should be created in the filesystem (before processing data through DTIPrep) if they don't exist

- Ouput:  - $QCoutdir   = directory where processed files for the candidate, visit label and DTIPrep protocol will be stored. 
=cut
sub getOutputDirectories {
    my ($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep)    = @_;    

    my ($QCoutdir)  = &DTI::createOutputFolders($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep);
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
Fetch the raw DWI datasets and foreach DWI, determine output names to be used and store them into a hash ($DTIrefs).

- Inputs:   - $nativedir    = native directory to look for native DWI dataset.
            - $DTI_volumes  = number of volumes expected in the DWI dataset.
            - $t1_scan_type = the scan type name of the T1 weighted dataset.
            - $QCoutdir     = directory to save processed files.
            - $DTIPrepProtocol= XML DTIPrep protocol to be used to process DWI datasets.

- Outputs:  - Will return undef if could not find any raw DWI dataset. 
            - Will return the list of raw DTIs found and a hash with the preprocessing output names and paths if raw DWI dataset was found.
            - Will also print relevant information in the log file.
=cut
sub fetchData {
    my ($nativedir, $DTI_volumes, $t1_scan_type, $QCoutdir, $DTIPrepProtocol, $protXMLrefs, $QCed2_step)  = @_;

    # Get DTI datasets
    my ($DTIs_list)    = &DTI::getRawDTIFiles($nativedir, $DTI_volumes);   
    if  (@$DTIs_list == 0) {
        print LOG "\n#############################\n";
        print LOG "\nWARNING: Could not find DTI files with $DTI_volumes volumes for in $nativedir.\n";
        print LOG "\n#############################\n";
        return undef;
    }

    # Get anatomical data
    my ($anat)  = &DTI::getAnatFile($nativedir, $t1_scan_type);

    ## Create a hash with raw dti as first level key, processed file type as second level key and processed file names as values. See example:
    #   dti_file_1  -> Raw_nrrd     => outputname
    #               -> QCed_nrrd    => outputname etc... (QCTxtReport, QCXmlReport, QCed_minc, QCProt)
    #   dti_file_2  -> Raw_nrrd     => outputname etc...
    my ($DTIrefs)   = &DTI::createDTIhashref($DTIs_list, $anat, $QCoutdir, $DTIPrepProtocol, $protXMLrefs, $QCed2_step); 

    return ($DTIs_list, $DTIrefs);
}






=pod
Function that creates the output folders, get the raw DTI files, convert them to nrrd and run DTIPrep using a bcheck protocol and a nobcheck protocol.

Inputs: - $DTIs_list    = list of DWI datasets to preprocess through DTIPrep for a given candidate and visit.
        - $DTIrefs      = hash where all output file names and paths for the different DWI are stored.
        - $QCoutdir     = output directory to use to save preprocessed files.
        - $DTIPrepProtocol= XML DTIPrep protocol to be used to preprocess the DWI dataset.

Outputs: - Will return undef if preprocessing was not successful on a least one raw DWI dataset
         - Will return 1 if at least one raw DWI dataset was successfully preprocessed
=cut
sub preprocessingPipeline {
    my ($DTIs_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol)  = @_;

    my $at_least_one_success    = 0;
    foreach my $dti_file (@$DTIs_list) {

        my $raw_nrrd    = $DTIrefs->{$dti_file}{'Raw_nrrd'};
        my $QCed_nrrd   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed_nrrd'};
        my $QCProt      = $DTIrefs->{$dti_file}{'Preproc'}{'QCProt'};
        my $QCed2_nrrd  = $DTIrefs->{$dti_file}{'Preproc'}{'QCed2_nrrd'};

        # Run Preprocessing pipeline
        print LOG "Running preprocessing pipeline on $dti_file (...)\n";
        # 1. convert raw DTI minc file to nrrd
        print LOG "\t1. Convert raw minc DTI to nrrd.\n";
        my ($convert_status)    = &preproc_mnc2nrrd($raw_nrrd, $dti_file);
        # 2. run DTIPrep pipeline on the raw nrrd file
        print LOG "\t2. Run DTIPrep.\n"; 
        my ($DTIPrep_status)    = &preproc_DTIPrep($QCed_nrrd, $raw_nrrd, $DTIPrepProtocol, $QCed2_nrrd);
        # 3. copy DTIPrep XML protocol used
        print LOG "\t3. Copy XML protocol used in output directory\n";
        my ($copyProt_status)   = &preproc_copyXMLprotocol($QCProt, $QCoutdir, $DTIPrepProtocol);

        # If one of the steps above failed, preprocessing status will be set to failed for this dti_file, otherwise it will be set to success.
        if ((!$convert_status) || (!$DTIPrep_status) || (!$copyProt_status)) {
            print LOG " => Preprocessing DTIPrep pipeline failed on $dti_file\n";
            $DTIrefs->{$dti_file}{'preproc_status'} = "failed";
        } else {
            print LOG " => DTIPrep was successfully run on $dti_file!\n";
            $DTIrefs->{$dti_file}{'preproc_status'} = "success";
            # add 1 to varaible $at_least_one_success
            $at_least_one_success++;
        }
    }

    #Return undef if variable $at_least_one success is null, otherwise return 1.
    if ($at_least_one_success == 0) {
        return undef;
    } else {
        return 1;
    }
}                                                  







=pod
Function that convert minc raw DWI file to nrrd and log the conversion status.
Inputs: - $raw_nrrd = Raw nrrd file to create
        - $dti_file = Raw DWI file to convert to nrrd
Output: - Will return undef if conversion failed, 
        - Will return 1 if conversion is a success.
=cut
sub preproc_mnc2nrrd {
    my ($raw_nrrd, $dti_file) = @_;
    
    if (-e $raw_nrrd) {
        print LOG "\t\t -> Raw DTI already converted to nrrd.\n";
        # set $convert_status to 1 as converted file already exists.
        return 1;
    } else {
        my ($convert_status)   = &DTI::convert_DTI($dti_file, $raw_nrrd, '--short --minc-to-nrrd');
        print LOG "\t\t -> Raw DTI successfully converted to nrrd!\n"       if ($convert_status);
        print LOG "\t\t -> ERROR: Raw DTI mnc2nrrd conversion failed!\n"    if (!$convert_status);
        return $convert_status;
    }
}






=pod
This function will call DTI::runDTIPrep to run DTIPrep on the raw nrrd file.
Inputs: - $QCed_nrrd        = QCed DWI nrrd file to be created by DTIPrep
        - $raw_nrrd         = Raw DWI nrrd file to process through DTIPrep
        - $DTIPrepProtocol  = DTIPrep XML Protocol to use to run DTIPrep
Output: - Will return 1 if QCed nrrd already exist
        - Will return $DTIPrep_status if DTIPrep is run. (DTIPrep_status can be equal to 1 if DTIPrep ran successfully, or undef if something went bad while running DTIPrep).
=cut
sub preproc_DTIPrep {
    my ($QCed_nrrd, $raw_nrrd, $DTIPrepProtocol, $QCed2_nrrd) = @_;

    if (-e $QCed_nrrd) {
        print LOG "\t\t -> QCed nrrd file already exists (DTIPrep was already run).\n";
        return 1;
    } else {
        my ($DTIPrep_status)   = &DTI::runDTIPrep($raw_nrrd, $DTIPrepProtocol, $QCed_nrrd, $QCed2_nrrd)  if (-e $raw_nrrd);
        print LOG "\t\t -> DTIPrep was successfully run. QCed nrrd is $QCed_nrrd.\n"                    if ($DTIPrep_status);
        print LOG "\t\t -> ERROR: DTIPrep failed. \n"                                                   if (!$DTIPrep_status);
        return $DTIPrep_status;
    }
}







=pod
Function that will call DTI::copyDTIPrepProtocol if the XML protocol has not already been copied in DTIPrep QC outdir.
Inputs: - $QCProt           = Copied QC XML protocol (in QC output folder)
        - $QCoutdir         = QC output directory
        - $DTIPrepProtocol  = DTIPrep XML protocol used to run DTIPrep
Output: - Will return 1 if XML protocol has already been copied 
        - Or will return $copyProt_status from DTI::copyDTIPrepProtocol (which will be either equal to 1 if copy was successful or undef if copy failed).
=cut
sub preproc_copyXMLprotocol {
    my ($QCProt, $QCoutdir, $DTIPrepProtocol) = @_;

    if (-e $QCProt) {
        print LOG "\t\t -> DTIPrep protocol was already copied in output directory $QCoutdir.\n";
        return 1;
    } else {
        my ($copyProt_status)  = &DTI::copyDTIPrepProtocol($DTIPrepProtocol, $QCProt);
        print LOG "\t\t -> DTIPrep protocol successfully copied in output directory $QCoutdir.\n"   if ($copyProt_status);
        print LOG "\t\t -> ERROR: Failed to copy DTIPrep protocol in output directory. \n\t Protocol to copy is: $DTIPrepProtocol. \n\tOutput directory is $QCoutdir.\n"   if (!$copyProt_status);
        return $copyProt_status;
    }
}        







=pod
This function will check preprocessing outputs and call convert2mnc, which will convert and reinsert headers into minc file.
Inputs: - $DTIs_list        = list of raw DWI that were processed
        - $DTIrefs          = hash with list of raw DTIs as a key and corresponding output names as values
        - $data_dir         = directory containing raw DWI dataset
        - $QCoutdir         = directory containing preprocessed outputs
        - $DTIPrepProtocol  = DTIPrep XML protocol used to run DTIPrep
        - $DTIPrepVersion   = DTIPrep version that was run to preprocess images
Output: - Will return undef if could not find preprocessed files or convert it to minc. 
        - Will return 1 if conversion was a success and all preprocessing files were found in QC outdir.
=cut
sub check_and_convertPreprocessedFiles {
    my ($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion)  = @_;

    my $at_least_one_success    = 0;
    foreach my $dti_file (@$DTIs_list) {

        # Check if all DTIPrep preprocessing (and postprocessing) outputs are available
        my ($foundPreprocessed) = &checkPreprocessOutputs($dti_file, $DTIrefs, $QCoutdir, $DTIPrepProtocol);

        # Convert QCed_nrrd DTI to minc   
        my ($convert_status)    = &convert2mnc($dti_file, $DTIrefs, $data_dir, $DTIPrepVersion) if ($foundPreprocessed);

        # If one of the steps above failed, postprocessing status will be set to failed for this dti_file, otherwise it will be set to success.
        if ($convert_status && $foundPreprocessed) {
            print LOG "QCed data was found and successfuly converted to minc for $dti_file\n";
            $DTIrefs->{$dti_file}{'preproc_convert_status'}    = "success";
            $at_least_one_success++;
        } else {
            print LOG "Failed to find QCed data for $dti_file\n"            if (!$foundPreprocessed);
            print LOG "Failed to convert QCed data to minc for $dti_file\n" if (!$convert_status);
            $DTIrefs->{$dti_file}{'preproc_convert_status'}    = "failed";
        }
    }

    #Return undef if variable $at_least_one success is null, otherwise return 1.
    if ($at_least_one_success == 0) {
        return undef;
    } else {
        return 1;    
    }
}









=pod
Check if all Preprocessing DTIPrep files are in the output folder.
They should include: - QCed nrrd file
                     - DTIPrep QC text report
                     - DTIPrep QC xml report
                     - & a copy of the protocol used to run DTIPrep (QCProt)
Inputs: - $dti_file         = raw DWI file that was processed
        - $DTIrefs          = hash containing output names
        - $QCoutdir         = preprocessing output directory
        - $DTIPrepProtocol  = DTIPrep XML protocol that was used to run DTIPrep
Output: - Will return 1 if all output files could be found 
        - Will return undef if at least one output file is missing. 
Relevant information will also be printed in the log file.
=cut
sub checkPreprocessOutputs {
    my ($dti_file, $DTIrefs, $QCoutdir, $DTIPrepProtocol)  = @_;

    my $QCed_nrrd   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed_nrrd'};
    my $QCTxtReport = $DTIrefs->{$dti_file}{'Preproc'}{'QCTxtReport'};
    my $QCXmlReport = $DTIrefs->{$dti_file}{'Preproc'}{'QCXmlReport'};
    my $QCProt      = $DTIrefs->{$dti_file}{'Preproc'}{'QCProt'};
    my $QCed2_nrrd  = $DTIrefs->{$dti_file}{'Preproc'}{'QCed2_nrrd'};

    my $err_message = "\nERROR: Could not find all DTIPrep preprocessing outputs in $outdir.\n" .
                        "\tQCed nrrd:   $QCed_nrrd\n"   .
                        "\tQCTxtReport: $QCTxtReport\n" .
                        "\tQCXmlReport: $QCXmlReport"   .
                        "\tQCProt:      $QCProt\n"      ;

    # if all outputs exists return 1, otherwise return undef
    if ((-e $QCed_nrrd) && (-e $QCTxtReport) && (-e $QCXmlReport) && (-e $QCProt)) {
        # additional check of output existence depending on whether $QCed2_minc is defined (secondary output produced by DTIPrep)
        if ((($QCed2_nrrd) && (-e $QCed2_nrrd)) || (!$QCed2_nrrd)) {
            print LOG "All DTIPrep preprocessing outputs were found in $outdir.\n";
            return 1;
        } else {
            print LOG $err_message;
            return undef;
        }
    } else {
        print LOG $err_message;
        return undef;
    }
}    







=pod
This function will convert to minc DTI QCed nrrd file from DTIPrep and reinsert all mincheader informations.
Inputs: - $dti_file         = Raw DWI file to be processed
        - $DTIrefs          = Hash containing output names
        - $data_dir         = Directory containing the raw dataset
        - $DTIPrepVersion   = DTIPrep version used to preprocess raw DWI
Output: - Will return 1 if QCed minc file has been created or already exists
        - Will return undef if QCed DWI was not successfully converted to minc
=cut
sub convert2mnc {
    my ($dti_file, $DTIrefs, $data_dir, $DTIPrepVersion)   = @_;

    my $QCed_nrrd   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed_nrrd'};
    my $QCed_minc   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed_minc'};
    my $QCTxtReport = $DTIrefs->{$dti_file}{'Preproc'}{'QCTxtReport'};
    my $QCed2_nrrd  = $DTIrefs->{$dti_file}{'Preproc'}{'QCed2_nrrd'};
    my $QCed2_minc  = $DTIrefs->{$dti_file}{'Preproc'}{'QCed2_minc'};

    # Convert QCed nrrd file back into minc file (with updated header)
    my  ($insert_header, $convert_status);
    if  (-e $QCed_nrrd) {
        if ( ((!$QCed_minc) && (-e $QCed_minc)) 
                || (($QCed2_minc) && (-e $QCed_minc) && (-e $QCed2_minc))) {
            print LOG "QCed minc(s) already exist(s).\n";
            return 1;
        } else {
            # convert QCed file to minc
            ($convert_status)   = &DTI::convert_DTI($QCed_nrrd,  $QCed_minc,  '--nrrd-to-minc');
            ($convert_status)   = &DTI::convert_DTI($QCed2_nrrd, $QCed2_minc, '--nrrd-to-minc') if (($QCed2_minc) && ($convert_status));
            # insert mincheader fields stored in raw dti_file (aside from the fields with direction information) into QCed minc file
            ($insert_header)    = &DTI::insertMincHeader($dti_file, $data_dir, $QCed_minc, $QCTxtReport, $DTIPrepVersion);
            ($insert_header)    = &DTI::insertMincHeader($dti_file, $data_dir, $QCed2_minc, $QCTxtReport, $DTIPrepVersion) if (($QCed2_minc) && ($insert_header));
        }
    }
    
    if (($convert_status) && ($insert_header)) {
        print LOG "QCed DTI successfully converted to minc.\n";
        return 1;
    } else {
        return undef;
    }
}










=pod
Post processing pipeline will:
    - check if post processing outputs already exists
    - if no post-processed outputs, it will call &runMincdiffusion to run mincdiffusion tools
Inputs: - $DTIs_list        = list with raw DWI to post-process
        - $DTIrefs          = hash containing output names and paths
        - $data_dir         = directory hosting raw DWI dataset
        - $QCoutdir         = QC process output directory
        - $DTIPrepProtocol  = DTIPrep XML protocol used to run DTIPrep
        - $DTIPrepVersion   = DTIPrep version 
Output: - Will return undef if post-processing outputs could not be created
        - Will return 1 if post-processing outputs was sucessfully created or already created
=cut
sub mincdiffusionPipeline {
    my ($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion, $niak_path)  = @_;    

    my $at_least_one_success    = 0;
    foreach my $dti_file (@$DTIs_list) {
        # Initialize variables
        my $QCed_minc   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed_minc'};

        # Check that FA, MD, RGB, RGB pic, baseline frame are not already created
        my ($already_created)   = &checkPostProcessedOutputs($dti_file, $DTIrefs, $QCoutdir);
        if ($already_created) {
            print LOG "Mincdiffusion tools were already run on $QCed_minc\n";
            $DTIrefs->{$dti_file}{'mincdiff_status'}   = "already_done";
            $at_least_one_success++;
            next;
        }

        # Check that QCed minc file exists first!
        if (!$QCed_minc) {
            print LOG "ERROR: could not find any QCed minc to run mincdiffusion tools\n";
            $DTIrefs->{$dti_file}{'mincdiff_status'}   = "failed";
            next;
        }

        # Run mincdiffusion tools 
        print LOG "Running mincdiffusion tools on $QCed_minc (...)\n";
        my ($mincdiff_status)   = &runMincdiffusionTools($dti_file, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepVersion, $niak_path);

        # If mincdiff_status is undef (mincdiffusion failed to create output files), mincdiff_status will be set to failed for this dti_file, otherwise it will be set to success.
        if ($mincdiff_status) {
            print LOG " => Successfully ran mincdiffusion tools on $QCed_minc!\n";
            $DTIrefs->{$dti_file}{'mincdiff_status'}    = "success";
            $at_least_one_success++;
        } else {
            print LOG " => diff_preprocess.pl failed on $QCed_minc.\n"         if (!$DTIrefs->{$dti_file}{'mincdiff_preprocess_status'});
            print LOG " => minctensor.pl failed on preprocessed $QCed_minc.\n" if (!$DTIrefs->{$dti_file}{'minctensor_status'});
            $DTIrefs->{$dti_file}{'mincdiff_status'}    = "failed";
        }
    }

    #Return undef if variable $at_least_one success is null, otherwise return 1.
    if ($at_least_one_success == 0) {
        return undef;
    } else {
        return 1;    
    }
}








=pod
Function that check if all outputs are present in the QC output directory.
Inputs: - $dti_file = raw DWI dataset to use as a key in $DTIrefs
        - $DTIrefs  = hash containing output names
        - $QCoutdir = QC output directory 
Output: - return 1 if all post processing outputs were found
        - return undef if could not find all post processing outputs
=cut
sub checkPostProcessedOutputs {
    my ($dti_file, $DTIrefs, $QCoutdir)  = @_;

        # diff_preprocess.pl outputs
    my $baseline    = $DTIrefs->{$dti_file}{'Postproc'}{'baseline_minc'}    ;
    my $preproc_minc= $DTIrefs->{$dti_file}{'Postproc'}{'preproc_minc'};
    my $anat_mask   = $DTIrefs->{$dti_file}{'Postproc'}{'anat_mask_minc'}   ;
        # minctensor.pl outputs
    my $FA          = $DTIrefs->{$dti_file}{'Postproc'}{'FA_minc'}          ;
    my $MD          = $DTIrefs->{$dti_file}{'Postproc'}{'MD_minc'}          ;
    my $RGB         = $DTIrefs->{$dti_file}{'Postproc'}{'RGB_minc'}         ;

    if ((-e $baseline) 
            && (-e $preproc_minc) 
            && (-e $anat_mask) 
            && (-e $FA)
            && (-e $MD)
            && (-e $RGB)) {
        print LOG "All DTIPrep postprocessing outputs were found in $outdir.\n";
        return 1;
    } else {
        print LOG "\nERROR: Could not find all DTIPrep postprocessing outputs in $outdir.\n" .
                    "\tbaseline (frame 0):         $baseline\n"    .
                    "\tmincdiffusion preprocessed: $preproc_minc\n".
                    "\tmincdiffusion anat mask:    $anat_mask\n"   .
                    "\tFA file:     $FA\n"   .
                    "\tMD file:     $MD\n"   .
                    "\tRGB file:    $RGB\n";
        return undef;
    }
}    













=pod
Will create FA, MD and RGB maps.
Inputs: - $dti_file         = raw DWI file that is used as a key in $DTIrefs
        - $DTIrefs          = hash containing output names and paths
        - $data_dir         = directory containing raw datasets
        - $QCoutdir         = QC output directory
        - $DTIPrepVersion   = DTIPrep version used
Output: - Return 1 if mincdiffusion pipeline was successful
        - Return undef if at least one step of the mincdiffusion pipeline failed
=cut
sub runMincdiffusionTools {
    my ($dti_file, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepVersion, $niak_path) = @_;

    # 1. Initialize variables
        # Raw anatomical
    my $raw_anat    = $DTIrefs->{$dti_file}{'raw_anat_minc'}; 
        # DTIPrep preprocessing outputs
    my $QCed_minc   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed_minc'}      ;
    my $QCTxtReport = $DTIrefs->{$dti_file}{'Preproc'}{'QCTxtReport'}    ;
        # diff_preprocess.pl outputs
    my $baseline    = $DTIrefs->{$dti_file}{'Postproc'}{'baseline_minc'} ;
    my $preproc_minc= $DTIrefs->{$dti_file}{'Postproc'}{'preproc_minc'}  ;
    my $anat_mask   = $DTIrefs->{$dti_file}{'Postproc'}{'anat_mask_minc'};
        # minctensor.pl outputs
    my $FA          = $DTIrefs->{$dti_file}{'Postproc'}{'FA_minc'}       ;
    my $MD          = $DTIrefs->{$dti_file}{'Postproc'}{'MD_minc'}       ;
    my $RGB         = $DTIrefs->{$dti_file}{'Postproc'}{'RGB_minc'}      ;

    # 2. Run mincdiffusion tools
    my ($mincdiff_preproc_status, $minctensor_status);
        # a. run diff_preprocess.pl via function mincdiff_preprocess
    if ((-e $baseline) && (-e $preproc_minc) && ($anat_mask)) {
        $mincdiff_preproc_status    = 1;
    } else {
        ($mincdiff_preproc_status)  = &DTI::mincdiff_preprocess($dti_file, $DTIrefs, $QCoutdir);
    }
        # b. run minctensor.pl via function mincdiff_minctensor
    if ((-e $FA) && (-e $MD) && (-e $RGB)) {
        $minctensor_status      = 1;
    } else {
        ($minctensor_status)    = &DTI::mincdiff_minctensor($dti_file, $DTIrefs, $QCoutdir, $niak_path);
    }

    # Write return statement
    if (($mincdiff_preproc_status) && ($minctensor_status)) { 
        return 1;
    } else {
        $DTIrefs->{$dti_file}{'mincdiff_preproc_status'}= $mincdiff_preproc_status;
        $DTIrefs->{$dti_file}{'minctensor_status'}      = $minctensor_status;
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


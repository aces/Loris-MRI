#!/usr/bin/perl -w

=pod

=head1 NAME

DTIPrep_pipeline.pl -- Run C<DTIPrep> and/or insert C<DTIPrep>'s outputs in the
database.

=head1 SYNOPSIS

perl DTIPrep_pipeline.p C<[options]>


-profile             : name of config file in
                        C<../dicom-archive/.loris_mri>

-list                : file containing the list of raw diffusion MINC
                        files (in C<assembly/DCCID/Visit/mri/native>)

-DTIPrepVersion      : C<DTIPrep> version used (if cannot be found in
                        C<DTIPrep> binary path)

-mincdiffusionVersion: C<mincdiffusion> release version used (if cannot be
                        found in C<mincdiffusion> scripts path)

-runDTIPrep          : if set, run C<DTIPrep> on the raw MINC DTI data

-DTIPrepProtocol     : C<DTIPrep> protocol to use (or used) to run C<DTIPrep>

-registerFilesInDB   : if set, registers outputs file in the database


B<Notes:>

- tool version options (C<-DTIPrepVersion> & C<-mincdiffusionVersion>)
do not need to be set if they can be found directly in the path of the binary
tools.

- the script can be run without the C<-runDTIPrep> option if execution of
C<DTIPrep> is not needed.

- the script can be run without the C<-registerFilesInDB> option if
registration of C<DTIPrep> is not needed.

=head1 DESCRIPTION

C<DTIPrep_pipeline.pl> can be used to run C<DTIPrep> on native DWI datasets. It
will also organize, convert and register the outputs of C<DTIPrep> in the
database.

If C<-runDTIPrep> option is not set, C<DTIPrep> processing will be skipped
(C<DTIPrep> outputs being already available, as well as the C<DTIPrep> protocol
that was used).

B<This pipeline will:>

1) grep native DWI files from list of given native directories (C<-list> option)

2) create (or fetch if C<-runDTIPrep> not set) output directories based
   on the C<DTIPrep> version and protocol that are to be (or were) used
   for C<DTIPrep> processing

3) convert native DWI MINC file to NRRD and run C<DTIPrep> if C<-runDTIPrep>
   option is set

4) fetch C<DTIPrep> pre-processing outputs (QCed.nrrd, QCReport.txt,
   QCXMLResults.xml & protocol.xml)

5) convert pre-processed NRRD files back to MINC with all the header
   information (based on the native MINC file)

6) create post-processing files (FA, RGB maps...) with all the header
   information

7) call C<DTIPrepRegister.pl> to register the files in the database if
     C<-registerFilesInDB> is set

=head2 Methods

=cut


require 5.001;
use strict;
use Getopt::Tabular;
use MNI::Startup        qw(nocputimes);
use MNI::Spawn;
use MNI::FileUtilities  qw(check_output_dirs);
use File::Basename;
use XML::Simple;
use Cwd 'abs_path';

# These are to load the DBI & DTI modules to be used
# use lib "$FindBin::Bin";
use NeuroDB::DBI;
use NeuroDB::ExitCodes;
use DTI::DTI;


#Set the help section
my $Usage   =   <<USAGE;

DTIPrep_pipeline.pl can be used to run DTIPrep on native DWI datasets, organize, convert and register the outputs of DTIPrep in the database.

If -runDTIPrep is not set, DTIPrep processing will be skipped (DTIPrep outputs being already available, as well as the DTIPrep protocol that was used).

This pipeline will:
    - fetch the native DWI files from the list of native directories given as input (-list option)
    - create (or fetch if -runDTIPrep not set) output directories based on the DTIPrep version and protocol that are to be (or were) used for DTIPrep processing.
    - convert native DWI minc file to nrrd and run DTIPrep if -runDTIPrep is set
    - fetch DTIPrep preprocessing outputs (QCed.nrrd, QCReport.txt, QCXMLResults.xml and protocol.xml)
    - convert pre-processed nrrd back to minc with all the header information (based on native minc)
    - create post-processing files (FA, RGB maps...) with all the header information
    - call DTIPrepRegister.pl to register the files in the database if -registerFilesInDB is set

Usage: $0 [options]

-help for options

Documentation: perldoc DTIPrep_pipeline.pl.

USAGE

# Set default option values
my $profile         = undef;
my $DTIPrepVersion  = undef;
my $mincdiffVersion = undef;
my $runDTIPrep      = 0;
my $DTIPrepProtocol = undef;
my $RegisterFiles   = undef;
my ($list, @args);

# Define the table describing the command-line options
my @args_table      = (["-profile",             "string",   1,      \$profile,          "name of config file in ../dicom-archive/.loris_mri"                               ],
                       ["-list",                "string",   1,      \$list,             "file containing the list of raw diffusion minc files (in assembly/DCCID/Visit/mri/native)."    ],
                       ["-DTIPrepVersion",      "string",   1,      \$DTIPrepVersion,   "DTIPrep version used (if cannot be found in DTIPrep binary path)."],
                       ["-mincdiffusionVersion","string",   1,      \$mincdiffVersion,  "mincdiffusion release version used (if cannot be found in mincdiffusion scripts path.)"],
                       ["-runDTIPrep",          "boolean",  1,      \$runDTIPrep,       "if set, run DTIPrep tool on the raw minc DTI data."               ],
                       ["-DTIPrepProtocol",     "string",   1,      \$DTIPrepProtocol,  "DTIPrep protocol to use or that was used to run DTIPrep tool."    ],
                       ["-registerFilesInDB",   "boolean",  1,      \$RegisterFiles,    "If set, it will register processed outputs into the database."    ]
                      );

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;


# input options error checking
if ( !$profile ) {
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}

# Determine DTIPrepVersion from its absolute path if DTIPrepVersion is not given as an argument when calling the script
($DTIPrepVersion)   = &identify_tool_version("DTIPrep", '\/(DTIPrep[A-Z0-9._]+)\/DTIPrep$')     if (!$DTIPrepVersion);
# Exit with error message if $DTIPrepVersion was not set or found based on its absolute path
if (!$DTIPrepVersion) {
    print STDERR "$Usage\n\t ERROR: Pipeline version could not be determined "
                 . "via the path to DTIPrep binary. You need to specify which "
                 . "version of DTIPrep you will be using with -DTIPrepVersion "
                 . "option.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_TOOL_VERSION;
}

# Establish database connection
my  $dbh    =   &NeuroDB::DBI::connect_to_db(@Settings::db);

# These settings are in the ConfigSettings table
my  $t1_scan_type  = &NeuroDB::DBI::getConfigSetting(\$dbh, 't1_scan_type');
my  $DTI_volumes   = &NeuroDB::DBI::getConfigSetting(\$dbh, 'DTI_volumes');
my  $reject_thresh = &NeuroDB::DBI::getConfigSetting(\$dbh, 'reject_thresh');
my  $niak_path     = &NeuroDB::DBI::getConfigSetting(\$dbh, 'niak_path');
my  $QCed2_step    = &NeuroDB::DBI::getConfigSetting(\$dbh,'QCed2_step');
my  $site          = &NeuroDB::DBI::getConfigSetting(\$dbh, 'prefix');
my  $data_dir      = &NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath');
$data_dir          =~ s/\/$//;   # removing trailing / in $data_dir

# Needed for log file
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)   =   localtime(time);
my  $date   =   sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $logdir =   $data_dir . "/logs/DTIPrep_pipeline/";
system("mkdir -p -m 770 $logdir") unless (-e $logdir);
my  $log    =   $logdir . "DTI_QC" . $date . ".log";
open(LOG,">>$log");
print LOG "Log file, $date\n";
print LOG "DTIPrep version: $DTIPrepVersion\n\n";


# Determine DTIPrep output directory
my $outdir  =   $data_dir . "/pipelines/DTIPrep/" . $DTIPrepVersion;


# Parse through list of directories containing native DTI data (i.e. $data_dir/assembly/DCCID/Visit/mri/native)
open(DIRS,"<$list");
my  @nativedirs   =   <DIRS>;
close(DIRS);

# Loop through native directories
foreach my $nativedir (@nativedirs)   {
    chomp ($nativedir);
    # Remove double / and last / character from nativedir
    $nativedir  =~ s/\/\//\//;
    $nativedir  =~ s/\/$//;

    
    #######################
    ####### Step 1: #######  Get SubjectID and Visit label
    #######################
    my ($subjID, $visit) = &getIdentifiers($nativedir);
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

    # Additional checks to check whether DTIPrep or mincdiffusion tools will run post-processing. If the mincdiffusion tools will be used, then we should be able to have a version of the tool and the path to niak! 
    my $bCompute    = $protXMLrefs->{entry}->{DTI_bCompute}->{value};
    if (($bCompute eq 'No') && (!$mincdiffVersion)) {
        ($mincdiffVersion)  = &identify_tool_version("minctensor.pl", '\/(mincdiffusion-[A-Z0-9._-]+)\/');
        # Exit program if mincdiffVersion is not set (needed to run minctensor)
        if (!$mincdiffVersion) {
            print STDERR "\n\tERROR: mincdiffusion tool's version could "
                  . "not be determined.\n\n";
            exit $NeuroDB::ExitCodes::MISSING_TOOL_VERSION;
        }
        # Exit program if $niak_path is not set
        if  (!$niak_path) {
            print STDERR "\n\tERROR: variable niak_path need to be set in the "
                         . "config file if you plan to use mincdiffusion tools "
                         . "to process the DTI files.\n\n";
            exit $NeuroDB::ExitCodes::INVALID_PATH;
        }
    }


    #######################
    ####### Step 4: ####### - Fetch raw DTI files to process. 
    ####################### - Determine output names based on raw DTI file names and organize them into a hash ($DTIrefs). 
    my ($DTIs_list, $DTIrefs)= &fetchData($nativedir, $DTI_volumes, $t1_scan_type, $QCoutdir, $DTIPrepProtocol, $protXMLrefs, $QCed2_step);
    next if ((!$DTIs_list) || (!$DTIrefs));


    #######################
    ####### Step 5: ####### - Run preprocessing pipeline (mnc2nrrd + DTIPrep) if $runDTIPrep option is set. 
    #######################
    if ($runDTIPrep) {
        my ($pre_success)   = &preprocessingPipeline($DTIs_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol);
        # if no preprocessing pipeline was successful for this visit, go to the next directory.
        next if (!$pre_success);
    } else {
        print LOG "DTIPrep won't be run on this dataset. (-runDTIPrep option was not set)\n";
        print LOG "--------------------------------\n";
    }


    #######################
    ####### Step 6: ####### Check if DTIPrep outputs are available and convert nrrd files to mnc. 
    ####################### These outputs are:
    #                          - QCed.nrrd
    #                          - QCReport.txt
    #                          - XMLQCResult.xml
    my ($convert_success)   = &check_and_convertPreprocessedFiles($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion);
    # if no preprocessed files were found or conversion was not successful for this visit, go to the next directory.
    next if (!$convert_success);


    #######################
    ####### Step 7: #######    
    ####################### 
    # - If bCompute is not set in DTIPrep protocol will run mincdiffusion tools and create FA, MD, RGB... maps
    # - If bCompute is set in DTIPrep protocol, will convert DTIPrep processed nrrd file into minc files and reinsert relevant header information
    if ($bCompute eq 'No') {
        print LOG "\n##################\n";
        print LOG "# Run mincdiffusion on QCed file.";
        print LOG "\n##################\n";
        my ($post_success)  = &mincdiffusionPipeline($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $mincdiffVersion, $niak_path);
        print LOG "\t==> Mincdiffusion outputs were found.\n";
        next if (!$post_success);
    } elsif ($bCompute eq 'Yes') {
        my ($DTIPrep_post_success)  = &check_and_convert_DTIPrep_postproc_outputs($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepVersion); 
        next if (!$DTIPrep_post_success);
    } else {
        print LOG "\n\tERROR: Post processing tools won't be run for this dataset. \n";
        print LOG "--------------------------------\n";
        exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
    }


    #######################
    ####### Step 8: ####### Register files into the DB if $RegisterFiles option is defined
    #######################
    print LOG "\n##################\n";
    print LOG "# Register files into database.";
    print LOG "\n##################\n";
    if ($RegisterFiles) {
        &register_processed_files_in_DB($DTIs_list, 
                                        $DTIrefs, 
                                        $profile, 
                                        $QCoutdir, 
                                        $DTIPrepVersion, 
                                        $mincdiffVersion
                                       );
    } else {
        print LOG "\t==> Processed files won't be registered in the database.\n";
        next;
    }

}

exit $NeuroDB::ExitCodes::SUCCESS;










###############
## Functions ##
###############

=pod

=head3 identify_tool_version($tool, $match)

Function that determines the tool version used for processing.

INPUTS:
  - $tool : tool to search absolute path containing version information
  - $match: string to match to determine tool version

RETURNS: version of the tool found, or undef if version could not be
determined based on the path

=cut

sub identify_tool_version {
    my ($tool, $match) = @_;

    my $executable          = `which $tool`;
    my $executable_abspath  = abs_path("$executable");
    if ($executable_abspath =~ m/$match/i) {
        return $1;
    } else {
        return undef;
    }
}


=pod

=head3 getIdentifiers($nativedir)

Fetches C<CandID> and visit label from the native directory of the dataset to
process. Relevant information will also be printed in the log file.

INPUT: native directory of the dataset to process

RETURNS: undef if could not determine the site, C<CandID>, visit OR
  - $candID     : candidate DCCID
  - $visit_label: visit label

=cut

sub getIdentifiers {
    my ($nativedir) = @_;    

    my ($subjID, $visit) = &Settings::get_DTI_CandID_Visit($nativedir); 
    if ((!$subjID) || (!$visit))  {
        print LOG "\n#############################\n";
        print LOG "WARNING:Cannot find ID,visit for $nativedir\n";
        print LOG "\n#############################\n";
        return undef;
    }else{
        print LOG "\n################################\n";
        print LOG "subID" . "\t" . "visit". "\n";
        print LOG $subjID . "\t" . $visit . "\n";
        print LOG "--------------------------------\n";
        print     $subjID . "\t" . $visit . "\n";
        return ($subjID, $visit);
    }
}


=pod

=head3 getOutputDirectories($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep)

Determine pipeline's output directory based on the root C<$outdir>, C<DTIPrep>
protocol name, candidate ID C<CandID> and visit label:
C<outdir/ProtocolName/CandID/VisitLabel>

- If C<$runDTIPrep> is set, the function will create the output folders

- If C<$runDTIPrep> is not set, the function will check that the directory exists

INPUTS:
  - $outdir         : root directory for C<DTIPrep> outputs (in
                       C</data/$PROJECT/data/pipelines/DTIPrep/DTIPrep_version>)
  - $subjID         : candidate ID of the DTI dataset to be processed
  - $visit          : visit label of the DTI dataset to be processed
  - $DTIPrepProtocol: XML file with the C<DTIPrep> protocol to use
  - $runDTIPrep     : boolean, if output folders should be created in
                       the filesystem (before processing data through
                       C<DTIPrep>) if they don't exist

RETURNS: directory where processed files for the candidate, visit label and
DTIPrep protocol will be stored.

=cut

sub getOutputDirectories {
    my ($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep)    = @_;    

    my ($QCoutdir)  = &DTI::createOutputFolders($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep);
    if (!$QCoutdir) {
        my $verb_message;
        $verb_message = "create" if ($runDTIPrep );
        $verb_message = "find"   if (!$runDTIPrep);
        print LOG "\n#############################\n";
        print LOG "WARNING:Could not $verb_message QC out directory in $outdir for candidate $subjID, visit $visit and DTIPrep protocol $DTIPrepProtocol. \n";
        print LOG "\n#############################\n";
        return undef;
    } else {
        print LOG "DTIPrep out directory: " . $QCoutdir . "\n";
        print LOG "--------------------------------\n";
        return ($QCoutdir);
    }
}


=pod

=head3 fetchData($nativedir, $DTI_volumes, $t1_scan_type, $QCoutdir, $DTIPrepProtocol)

Fetches the raw DWI datasets and foreach DWI, determines output names to be used
and stores them into a hash (C<$DTIrefs>). Will also print relevant information
in the log file.

INPUTS:
  - $nativedir      : native directory to look for native DWI dataset
  - $DTI_volumes    : number of volumes expected in the DWI dataset
  - $t1_scan_type   : the scan type name of the T1 weighted dataset
  - $QCoutdir       : directory to save processed files
  - $DTIPrepProtocol: XML C<DTIPrep> protocol to use

RETURNS: undef if could not find any raw DWI dataset OR
  - $DTIs_list: list of raw DTIs found
  - $DTIrefs  : a hash with the pre-processing output names and paths

=cut

sub fetchData {
    my ($nativedir, $DTI_volumes, $t1_scan_type, $QCoutdir, $DTIPrepProtocol, $protXMLrefs, $QCed2_step)  = @_;

    # Get DTI datasets
    my ($DTIs_list)    = &DTI::getRawDTIFiles($nativedir, $DTI_volumes);   
    if  (@$DTIs_list == 0) {
        print LOG "\n#############################\n";
        print LOG "WARNING: Could not find DTI files with $DTI_volumes volumes for in $nativedir.\n";
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

=head3 preprocessingPipeline($DTIs_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol)

Function that creates the output folders, gets the raw DTI files, converts them
to NRRD and runs C<DTIPrep> using a C<bcheck> protocol and a C<nobcheck> protocol.

INPUTS:
  - $DTIs_list      : list of DWI files to process for a given C<CandID/Visit>
  - $DTIrefs        : hash with output file names & paths for the
                       different DWI to process
  - $QCoutdir       : output directory to save preprocessed files
  - $DTIPrepProtocol: XML C<DTIPrep> protocol to use for pre-processing

RETURNS:
  - 1 if at least one raw DWI dataset was successfully preprocessed
  - undef if pre-processing was not successful on a least one raw DWI dataset

=cut

sub preprocessingPipeline {
    my ($DTIs_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol)  = @_;

    my $at_least_one_success    = 0;
    foreach my $dti_file (@$DTIs_list) {

        my $raw_nrrd    = $DTIrefs->{$dti_file}{'Raw'}{'nrrd'};
        my $QCed_nrrd   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed'}{'nrrd'};
        my $QCProt      = $DTIrefs->{$dti_file}{'Preproc'}{'QCProt'}{'xml'};
        my $QCed2_nrrd  = $DTIrefs->{$dti_file}{'Preproc'}{'QCed2'}{'nrrd'};

        # Run Preprocessing pipeline
        print LOG "\n##################\n";
        print LOG "#Running preprocessing pipeline on $dti_file (...)";
        print LOG "\n##################\n";
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
            print LOG " \t==> Preprocessing DTIPrep pipeline failed on $dti_file\n";
            $DTIrefs->{$dti_file}{'preproc_status'} = "failed";
        } else {
            print LOG " \t==> All DTIPrep were found for $dti_file!\n";
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

=head3 preproc_mnc2nrrd($raw_nrrd, $dti_file)

Function that converts MINC raw DWI file to NRRD and logs the conversion status.

INPUTS:
  - $raw_nrrd: raw NRRD file to create
  - $dti_file: raw DWI file to convert to NRRD

RETURNS: 1 on success, undef on failure

=cut

sub preproc_mnc2nrrd {
    my ($raw_nrrd, $dti_file) = @_;
    
    if (-e $raw_nrrd) {
        print LOG "\t\t -> Raw DTI already converted to nrrd.\n";
        # set $convert_status to 1 as converted file already exists.
        return 1;
    } else {
        my ($convert_status)   = &DTI::convert_DTI($dti_file, $raw_nrrd, '--short --minc-to-nrrd --dwi');
        print LOG "\t\t -> Raw DTI successfully converted to nrrd!\n"       if ($convert_status);
        print LOG "\t\t -> ERROR: Raw DTI mnc2nrrd conversion failed!\n"    if (!$convert_status);
        return $convert_status;
    }
}


=pod

=head3 preproc_DTIPrep($QCed_nrrd, $raw_nrrd, $DTIPrepProtocol, $QCed2_nrrd)

This function will call C<&DTI::runDTIPrep> to run C<DTIPrep> on the raw NRRD file.

INPUTS:
  - $QCed_nrrd      : QCed DWI NRRD file to be created by C<DTIPrep>
  - $raw_nrrd       : raw DWI NRRD file to process through C<DTIPrep>
  - $DTIPrepProtocol: C<DTIPrep> XML Protocol to use to run C<DTIPrep>

RETURNS: 1 on success, undef on failure

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

=head3 preproc_copyXMLprotocol($QCProt, $QCoutdir, $DTIPrepProtocol)

Function that will call C<&DTI::copyDTIPrepProtocol> if the XML protocol has
not already been copied in C<DTIPrep> QC directory.

INPUTS:
  - $QCProt         : copied QC XML protocol (in QC output folder)
  - $QCoutdir       : QC output directory
  - $DTIPrepProtocol: C<DTIPrep> XML protocol used to run C<DTIPrep>

RETURNS: 1 on success, undef on failure

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

=head3 check_and_convertPreprocessedFiles($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion)

This function will check pre-processing outputs and call
C<&convertPreproc2mnc>, which will convert and reinsert headers into MINC file.

INPUTS:
  - $DTIs_list      : list of raw DWI that were pre-processed
  - $DTIrefs        : hash with list of raw DTIs as a key &
                       corresponding output names as values
  - $data_dir       : directory containing raw DWI dataset
  - $QCoutdir       : directory containing preprocessed outputs
  - $DTIPrepProtocol: C<DTIPrep> XML protocol used to run C<DTIPrep>
  - $DTIPrepVersion : C<DTIPrep> version that was run to pre-process images

RETURNS:
  - undef if could not find pre-processed files or convert them to MINC
  - 1 if successful conversion & all pre-processing files found in the QC directory

=cut

sub check_and_convertPreprocessedFiles {
    my ($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion)  = @_;

    my $at_least_one_success    = 0;
    foreach my $dti_file (@$DTIs_list) {

        # Check if all DTIPrep preprocessing (and postprocessing) outputs are available
        print LOG "\n##################\n";
        print LOG "# Check and convert preprocessed files.";
        print LOG "\n##################\n";
        my ($foundPreprocessed) = &checkPreprocessOutputs($dti_file, $DTIrefs, $QCoutdir, $DTIPrepProtocol);

        # Convert QCed_nrrd DTI to minc   
        my ($convert_status)    = &convertPreproc2mnc($dti_file, $DTIrefs, $data_dir, $DTIPrepVersion) if ($foundPreprocessed);

        # If one of the steps above failed, postprocessing status will be set to failed for this dti_file, otherwise it will be set to success.
        if ($convert_status && $foundPreprocessed) {
            print LOG "\t==> QCed data was found and converted to minc for $dti_file\n";
            $DTIrefs->{$dti_file}{'preproc_convert_status'}    = "success";
            $at_least_one_success++;
        } else {
            print LOG "\t==> WARNING: Failed to find QCed data for $dti_file\n"            if (!$foundPreprocessed);
            print LOG "\t==> WARNING: Failed to convert QCed data to minc for $dti_file\n" if (!$convert_status);
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

=head3 checkPreprocessOutputs($dti_file, $DTIrefs, $QCoutdir, $DTIPrepProtocol)

Checks if all pre-processing C<DTIPrep> files are in the output folder. They
should include:
  - QCed NRRD file
  - C<DTIPrep> QC text report
  - C<DTIPrep> QC XML report
  - a copy of the protocol used to run C<DTIPrep>

Relevant information will also be printed in the log file.

INPUTS:
  - $dti_file       : raw DWI file that was processed
  - $DTIrefs        : hash containing output names
  - $QCoutdir       : pre-processing output directory
  - $DTIPrepProtocol: C<DTIPrep> XML protocol that was used to run C<DTIPrep>

RETURNS: undef if at least one output file is missing; 1 if all output files
were found

=cut

sub checkPreprocessOutputs {
    my ($dti_file, $DTIrefs, $QCoutdir, $DTIPrepProtocol)  = @_;

    my $QCed_nrrd   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed'}{'nrrd'};
    my $QCTxtReport = $DTIrefs->{$dti_file}{'Preproc'}{'QCReport'}{'txt'};
    my $QCXmlReport = $DTIrefs->{$dti_file}{'Preproc'}{'QCReport'}{'xml'};
    my $QCProt      = $DTIrefs->{$dti_file}{'Preproc'}{'QCProt'}{'xml'};
    my $QCed2_nrrd  = $DTIrefs->{$dti_file}{'Preproc'}{'QCed2'}{'nrrd'};

    my $err_message = "\nERROR: Could not find all DTIPrep preprocessing outputs in $outdir.\n" .
                        "\tQCed nrrd:   $QCed_nrrd\n"   .
                        "\tQCTxtReport: $QCTxtReport\n" .
                        "\tQCXmlReport: $QCXmlReport"   .
                        "\tQCProt:      $QCProt\n"      ;

    print LOG "\t 1. Check that preprocessed files exist\n";
    # if all outputs exists return 1, otherwise return undef
    if ((-e $QCed_nrrd) && (-e $QCTxtReport) && (-e $QCXmlReport) && (-e $QCProt)) {
        # additional check of output existence depending on whether $QCed2_minc is defined (secondary output produced by DTIPrep)
        if ((($QCed2_nrrd) && (-e $QCed2_nrrd)) || (!$QCed2_nrrd)) {
            print LOG "\t\t-> All DTIPrep preprocessing outputs were found in $outdir.\n";
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

=head3 convertPreproc2mnc($dti_file, $DTIrefs, $data_dir, $DTIPrepVersion)

This function will convert to MINC DTI QCed NRRD file from C<DTIPrep> and reinsert
all MINC header information.

INPUTS:
  - $dti_file      : raw DWI file to be processed
  - $DTIrefs       : hash containing output names
  - $data_dir      : directory containing the raw dataset
  - $DTIPrepVersion: C<DTIPrep> version used to pre-process raw DWI

RETURNS: 1 if QCed MINC file created and exists; undef otherwise

=cut

sub convertPreproc2mnc {
    my ($dti_file, $DTIrefs, $data_dir, $DTIPrepVersion)   = @_;

    my $QCed_nrrd   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed'}{'nrrd'};
    my $QCed_minc   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed'}{'minc'};
    my $QCTxtReport = $DTIrefs->{$dti_file}{'Preproc'}{'QCReport'}{'txt'};
    my $QCed2_nrrd  = $DTIrefs->{$dti_file}{'Preproc'}{'QCed2'}{'nrrd'};
    my $QCed2_minc  = $DTIrefs->{$dti_file}{'Preproc'}{'QCed2'}{'minc'};

    print LOG "\t 2. Convert preprocessed files to minc\n";

    # Convert QCed nrrd file back into minc file (with updated header)
    my  ($insert_header, $convert_status);
    if  (-e $QCed_nrrd) {
        if ( ((!$QCed2_minc) && (-e $QCed_minc)) 
                || (($QCed2_minc) && (-e $QCed_minc) && (-e $QCed2_minc))) {
            print LOG "\t\t-> QCed minc(s) already exist(s).\n";
            return 1;
        } else {
            # convert QCed file to minc
            ($convert_status)   = &DTI::convert_DTI($QCed_nrrd,  $QCed_minc,  '--nrrd-to-minc --dwi');
            ($convert_status)   = &DTI::convert_DTI($QCed2_nrrd, $QCed2_minc, '--nrrd-to-minc --dwi') if (($QCed2_minc) && ($convert_status));
            # insert mincheader fields stored in raw dti_file (aside from the fields with direction information) into QCed minc file
            ($insert_header)    = &DTI::insertMincHeader($dti_file, $data_dir, $QCed_minc, $QCTxtReport, $DTIPrepVersion);
            ($insert_header)    = &DTI::insertMincHeader($dti_file, $data_dir, $QCed2_minc, $QCTxtReport, $DTIPrepVersion) if (($QCed2_minc) && ($insert_header));
        }
    }
    
    if (($convert_status) && ($insert_header)) {
        print LOG "\t\t-> QCed DTI successfully converted to minc.\n";
        return 1;
    } else {
        return undef;
    }
}


=pod

=head3 mincdiffusionPipeline($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, ...)

Running post-processing pipeline that will check if post-processing outputs
already exist. If they don't exist, it will call C<&runMincdiffusion> to run
the C<mincdiffusion> tools.

INPUTS:
  - $DTIs_list      : list with raw DWI to post-process
  - $DTIrefs        : hash containing output names and paths
  - $data_dir       : directory hosting raw DWI dataset
  - $QCoutdir       : QC process output directory
  - $DTIPrepProtocol: C<DTIPrep> XML protocol used to run C<DTIPrep>
  - $mincdiffVersion: C<mincdiffusion> version

RETURNS: 1 if all post-processing outputs found, undef otherwise

=cut

sub mincdiffusionPipeline {
    my ($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepProtocol, $mincdiffVersion, $niak_path)  = @_;    

    my $at_least_one_success    = 0;
    foreach my $dti_file (@$DTIs_list) {
        # Initialize variables
        my $QCed_minc   = $DTIrefs->{$dti_file}{'Preproc'}{'QCed'}{'minc'};

        # Check that FA, MD, RGB, RGB pic, baseline frame are not already created
        print LOG "\t1. Check if mincdiffusion outputs already exist\n";
        my ($already_created)   = &checkMincdiffusionPostProcessedOutputs($dti_file, $DTIrefs, $QCoutdir);
        if ($already_created) {
            print LOG "\t\t-> Mincdiffusion tools were already run on $QCed_minc\n";
            $DTIrefs->{$dti_file}{'mincdiff_status'}   = "already_done";
            $at_least_one_success++;
            next;
        }

        # Check that QCed minc file exists first!
        if (!$QCed_minc) {
            print LOG "ERROR: could not find any QCed minc to run mincdiffusion tools for $dti_file\n";
            $DTIrefs->{$dti_file}{'mincdiff_status'}   = "failed";
            next;
        }

        # Run mincdiffusion tools 
        print LOG "\t2. Running mincdiffusion tools on $QCed_minc (...)\n";
        my ($mincdiff_status)   = &runMincdiffusionTools($dti_file, $DTIrefs, $data_dir, $QCoutdir, $mincdiffVersion, $niak_path);

        # If mincdiff_status is undef (mincdiffusion failed to create output files), mincdiff_status will be set to failed for this dti_file, otherwise it will be set to success.
        if ($mincdiff_status) {
            print LOG "\t\t-> Successfully ran mincdiffusion tools on $QCed_minc!\n";
            $DTIrefs->{$dti_file}{'mincdiff_status'}    = "success";
            $at_least_one_success++;
        } else {
            print LOG "\t\t-> diff_preprocess.pl failed on $QCed_minc.\n"         if (!$DTIrefs->{$dti_file}{'mincdiff_preprocess_status'});
            print LOG "\t\t-> minctensor.pl failed on preprocessed $QCed_minc.\n" if (!$DTIrefs->{$dti_file}{'minctensor_status'});
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

=head3 checkMincdiffusionPostProcessedOutputs($dti_file, $DTIrefs, $QCoutdir)

Function that checks if all outputs are present in the QC output directory.

INPUTS:
  - $dti_file: raw DWI dataset to use as a key in C<$DTIrefs>
  - $DTIrefs : hash containing output names
  - $QCoutdir: QC output directory

RETURNS: 1 if all post processing outputs were found, undef otherwise

=cut

sub checkMincdiffusionPostProcessedOutputs {
    my ($dti_file, $DTIrefs, $QCoutdir)  = @_;

        # diff_preprocess.pl outputs
    my $baseline        = $DTIrefs->{$dti_file}{'Postproc'}{'baseline'}{'minc'};
    my $preproc_minc    = $DTIrefs->{$dti_file}{'Postproc'}{'preproc'}{'minc'};
    my $anat_mask       = $DTIrefs->{$dti_file}{'Postproc'}{'anat_mask'}{'minc'};
    my $anat_mask_diff  = $DTIrefs->{$dti_file}{'Postproc'}{'anat_mask_diff'}{'minc'};
        # minctensor.pl outputs
    my $FA              = $DTIrefs->{$dti_file}{'Postproc'}{'FA'}{'minc'};
    my $MD              = $DTIrefs->{$dti_file}{'Postproc'}{'MD'}{'minc'};
    my $RGB             = $DTIrefs->{$dti_file}{'Postproc'}{'RGB'}{'minc'};

    if ((-e $baseline) 
            && (-e $preproc_minc) 
            && (-e $anat_mask) 
            && (-e $anat_mask_diff) 
            && (-e $FA)
            && (-e $MD)
            && (-e $RGB)) {
        print LOG "\t\t-> All mincdiffusion postprocessing outputs were found in $outdir.\n";
        return 1;
    } else {
        print LOG "\nERROR: Could not find all mincdiffusion postprocessing outputs in $outdir.\n" .
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

=head3 runMincdiffusionTools($dti_file, $DTIrefs, $data_dir, $QCoutdir, $mincdiffVersion)

Will create FA, MD and RGB maps.

INPUTS:
  - $dti_file       : raw DWI file that is used as a key in C<$DTIrefs>
  - $DTIrefs        : hash containing output names and paths
  - $data_dir       : directory containing raw datasets
  - $QCoutdir       : QC output directory
  - $mincdiffVersion: C<mincdiffusion> version used

RETURNS: 1 on success, undef on failure

=cut

sub runMincdiffusionTools {
    my ($dti_file, $DTIrefs, $data_dir, $QCoutdir, $mincdiffVersion, $niak_path) = @_;

    # 1. Initialize variables
        # Raw anatomical
    my $raw_anat        = $DTIrefs->{$dti_file}{'raw_anat'}{'minc'}; 
        # DTIPrep preprocessing outputs
    my $QCed_minc       = $DTIrefs->{$dti_file}{'Preproc'}{'QCed'}{'minc'};
    my $QCTxtReport     = $DTIrefs->{$dti_file}{'Preproc'}{'QCReport'}{'txt'};
        # diff_preprocess.pl outputs
    my $baseline        = $DTIrefs->{$dti_file}{'Postproc'}{'baseline'}{'minc'};
    my $preproc_minc    = $DTIrefs->{$dti_file}{'Postproc'}{'preproc'}{'minc'};
    my $anat_mask       = $DTIrefs->{$dti_file}{'Postproc'}{'anat_mask'}{'minc'};
    my $anat_mask_diff  = $DTIrefs->{$dti_file}{'Postproc'}{'anat_mask_diff'}{'minc'};
        # minctensor.pl outputs
    my $FA              = $DTIrefs->{$dti_file}{'Postproc'}{'FA'}{'minc'};
    my $MD              = $DTIrefs->{$dti_file}{'Postproc'}{'MD'}{'minc'};
    my $RGB             = $DTIrefs->{$dti_file}{'Postproc'}{'RGB'}{'minc'};

    # 2. Run mincdiffusion tools
    my ($mincdiff_preproc_status, $minctensor_status, $insert_header);
        # a. run diff_preprocess.pl via function mincdiff_preprocess
    if ((-e $baseline) && (-e $preproc_minc) && ($anat_mask) && ($anat_mask_diff)) {
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
        # c. Insert missing header information in the output minc files
    my $insert_success;
    if ((-e $baseline) && (-e $preproc_minc) && ($anat_mask) && ($anat_mask_diff)
            && (-e $FA) && (-e $MD) && (-e $RGB)) {

        my ($baseline_insert)       = &DTI::insertMincHeader($dti_file, $data_dir, $baseline,       $QCTxtReport, $mincdiffVersion);
        my ($preproc_insert)        = &DTI::insertMincHeader($dti_file, $data_dir, $preproc_minc,   $QCTxtReport, $mincdiffVersion);
        my ($anat_mask_insert)      = &DTI::insertMincHeader($raw_anat, $data_dir, $anat_mask,      $QCTxtReport, $mincdiffVersion, 1);
        my ($anat_mask_diff_insert) = &DTI::insertMincHeader($raw_anat, $data_dir, $anat_mask_diff, $QCTxtReport, $mincdiffVersion, 1);
        my ($fa_insert)             = &DTI::insertMincHeader($dti_file, $data_dir, $FA,             $QCTxtReport, $mincdiffVersion);
        my ($md_insert)             = &DTI::insertMincHeader($dti_file, $data_dir, $MD,             $QCTxtReport, $mincdiffVersion);
        my ($rgb_insert)            = &DTI::insertMincHeader($dti_file, $data_dir, $RGB,            $QCTxtReport, $mincdiffVersion);
        # if all minc header information are in post-processed files, set $insert_success to 1
        if (($baseline_insert) && ($preproc_insert) && ($anat_mask_insert) && ($anat_mask_diff_insert)) {
            $DTIrefs->{$dti_file}{'postproc_hdr_success'}   = "success";
            $insert_success = 1;
        } else {
            $DTIrefs->{$dti_file}{'postproc_hdr_success'}   = "failed";
        }
    }
    
    # Write return statement
    if (($mincdiff_preproc_status) && ($minctensor_status) && ($insert_success)) { 
        return 1;
    } else {
        return undef;
    }
}


=pod

=head3 check_and_convert_DTIPrep_postproc_outputs($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepVersion)

Function that loops through DTI files acquired for the C<CandID> and session to
check if C<DTIPrep> post processed NRRD files have been created and converts them
to MINC files with relevant header information.

INPUTS:
  - $DTIs_list     : list of DTI files for the session and candidate
  - $DTIrefs       : hash containing references for DTI output naming
  - $data_dir      : directory containing the raw DTI dataset
  - $QCoutdir      : directory containing the processed data
  - $DTIPrepVersion: version of C<DTIPrep> used to process the data

RETURNS: 1 on success, undef on failure

=cut

sub check_and_convert_DTIPrep_postproc_outputs {
    my ($DTIs_list, $DTIrefs, $data_dir, $QCoutdir, $DTIPrepVersion) = @_;

    my $at_least_one_success    = 0;
    foreach my $dti_file (@$DTIs_list) {
        
        # Check if all DTIPrep post-processing output were created
        my $QCTxtReport = $DTIrefs->{$dti_file}->{'Preproc'}->{'QCReport'}->{'txt'};
        my ($nrrds_found, $mincs_created, $hdrs_inserted)   = &DTI::convert_DTIPrep_postproc_outputs($dti_file, $DTIrefs, $data_dir, $QCTxtReport, $DTIPrepVersion);
        
        if (($nrrds_found) && ($mincs_created) && ($hdrs_inserted)) {
            print LOG "All DTIPrep post-processed data were found and successfuly converted to minc files with header information.\n";
            $DTIrefs->{$dti_file}{'postproc_convert_status'}= "success";
            $at_least_one_success++;
        } else {
            print LOG "DTIPrep post processing outputs could not be found in $QCoutdir.\n"  if (!$nrrds_found);
            print LOG "DTIPrep post processing outputs could not be converted in minc.\n"   if (!$mincs_created);
            print LOG "DTIPrep post processing minc files do not have complete header information. \n"  if (!$hdrs_inserted);
            next;
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

=head3 register_processed_files_in_DB($DTIs_list, $DTIrefs, $profile, $QCoutdir, $DTIPrepVersion, $mincdiffVersion)

Calls the script C<DTIPrepRegister.pl> to register processed files into the
database.

INPUT:
  - $DTIs_list      : list of native DTI files processed
  - $DTIrefs        : hash containing the processed filenames
  - $profile        : config file (in C<../dicom-archive/.loris_mri>)
  - $QCoutdir       : output directory containing the processed files
  - $DTIPrepVersion : C<DTIPrep> version used to obtain QCed files
  - $mincdiffVersion: C<mincdiffusion> tool version used

=cut

sub register_processed_files_in_DB {
    my ($DTIs_list, $DTIrefs, $profile, $QCoutdir, $DTIPrepVersion, $mincdiffVersion) = @_;

    # Loop through raw DTIs list 
    foreach my $dti_file (@$DTIs_list) {
        
        # If post processing pipeline used was mincdiffusion, we need to know which raw anatomical file was used to generate brain masks.
        # If post processing pipeline used was DTIPrep, no need to specify an anatomical raw dataset when calling DTIPrepRegister.pl
        my $postprocessingtool  = $DTIrefs->{$dti_file}->{'Postproc'}->{'Tool'};
        my $register_cmd;
        if ($postprocessingtool eq "DTIPrep") {

            $register_cmd    = "DTIPrepRegister.pl -profile $profile -DTIPrep_subdir $QCoutdir -DTIPrepProtocol \"$DTIPrepProtocol\" -DTI_file $dti_file -DTIPrepVersion \"$DTIPrepVersion\"";

        } elsif ($postprocessingtool eq "mincdiffusion") {

            # Extract the raw anat file used by mincdiffusion
            my $anat_file    = $DTIrefs->{$dti_file}->{'raw_anat'}{'minc'};
            $register_cmd    = "DTIPrepRegister.pl -profile $profile -DTIPrep_subdir $QCoutdir -DTIPrepProtocol \"$DTIPrepProtocol\" -DTI_file $dti_file -anat_file $anat_file -DTIPrepVersion \"$DTIPrepVersion\" -mincdiffusionVersion \"$mincdiffVersion\"";

        }
        print LOG "\t1. Registering files.\n";
        print LOG "\t\t-> Executed command: $register_cmd\n";
        system($register_cmd);
    }
}


__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut
#! /usr/bin/perl

use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use FindBin;
use Date::Parse;
use XML::Simple;
use lib "$FindBin::Bin";

use DB::DBI;
use DTI::DTI;

my $profile         = undef;
my $DTIPrep_subdir  = undef;
my $anat            = undef;
my $dti_file        = undef;
my $DTIPrepProtocol = undef;
my $DTIPrepVersion  = undef;
my $mincdiffVersion = undef;
my @args;


my  $Usage  =   <<USAGE;

This script fetchs the DTI_QC pipeline's output files of interest to be registered in the database and send them to register_processed_data.pl. The following files will be considered:
    - the QCed minc file produced by DTIPrep (i.e. DTI dataset without the bad directions detected by DTIPrep)
    - the QCReport produced by DTPrep if the option -txt is set
    - the XMLQCResult produced by DTIPrep if the option -xml is set
    - the RGB minc file produced by mincdiffusion (for quick red artefact QC)

The list of directories to search for DTI outputs will be given via STDIN. 

File convention: 
    - the QCed minc file should be named as *_QCed.mnc
    - the QCReport should be named as *_QCReport.txt
    - the XMLQCResult should be named as *_XMLQCResult.xml
    - the RGB map should be named as *_QCed_rgb.mnc

Usage: $0 [options]

-help for options

USAGE

my  @args_table = (
    ["-profile",              "string", 1,  \$profile,          "name of config file in ~/.neurodb."],
    ["-DTIPrep_subdir",       "string", 1,  \$DTIPrep_subdir,   "DTIPrep subdirectory where processed files to be registered in the database are stored"],
    ["-DTIPrepProtocol",      "string", 1,  \$DTIPrepProtocol,  "DTIPrep that was used to process the DTI dataset"],
    ["-DTI_file",             "string", 1,  \$dti_file,         "Raw DTI dataset that was processed through DTIPrep"],
    ["-anat_file",            "string", 1,  \$anat,             "Raw anatomical dataset that was used to create FA, RGB and other post-processed maps using mincdiffusion tools"],
    ["-DTIPrepVersion",       "string", 1,  \$DTIPrepVersion,   "DTIPrep version used if cannot be found in minc files's processing:pipeline header field."],
    ["-mincdiffusionVersion", "string", 1,  \$mincdiffVersion,  "mincdiffusion release version used if cannot be found in minc files's processing:pipeline header field."]
);

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# input option error checking
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" }
if  ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{HOME}/.neurodb/ \n\n"; 
    exit 33;
}

if (!$profile) {
    print "$Usage\n\tERROR: You must specify a profile.\n\n";  
    exit 33;
}

if (!$DTIPrep_subdir) {
    print "$Usage\n\tERROR: You must specify a DTIPrep subdirectory with processed files to be registered in the database.\n\n";
    exit 33;
}

if (!$dti_file) {
    print "$Usage\n\tERROR: You must specify the raw DTI file that was processed through DTIPrep.\n\n";
    exit 33;
}

if (!$DTIPrepProtocol) {
    print "$Usage\n\tERROR: You must specify the XML DTIPrep protocol used by DTIPrep.\n\n";
    exit 33;
}

if (!$DTIPrepVersion) {
    print "$Usage\n\tERROR: You must specify the version of DTIPrep used to process the DTI files.\n\n";
    exit 33;
}

# needed for log file
my  $data_dir    =  $Settings::data_dir;
my  $log_dir     =  "$data_dir/logs/DTIPrep_register";
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my  $date        =  sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log         =  "$log_dir/DTIregister$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

# DTIPrep step during which a secondary QCed file will be created (for example: noMC for a file without motion correction)
my  $QCed2_step =  $Settings::QCed2_step;

# establish database connection
my  $dbh    =   &DB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";

print LOG "\n==> DTI output directory is: $DTIPrep_subdir\n";



    #######################
    ####### Step 1: #######  Get list of output files
    #######################
# 1.a Read the DTIPrep XML protocol into a hash
my ($protXMLrefs)   = &DTI::readDTIPrepXMLprot($DTIPrepProtocol);
if (!$protXMLrefs) {
    print LOG "\n\tERROR: DTIPrep XML protocol could not be read.\n";
    exit 33;
}
# 1.b Create a hash containing names of all outputs created by DTIPrep/mincdiffusion pipeline
my @dti_files   = [$dti_file];  # createDTIhashref needs an array with dti_files
my ($DTIrefs)   = &DTI::createDTIhashref(@dti_files, 
                                         $anat, 
                                         $DTIPrep_subdir, 
                                         $DTIPrepProtocol, 
                                         $protXMLrefs, 
                                         $QCed2_step
                                        );
if  (!$DTIrefs) {
    print LOG "\nERROR:\n\tCould not determine list of outputs for $dti_file.\n";
    exit 33;
}
if ((!$mincdiffVersion) && ($DTIrefs->{$dti_file}->{'Postproc'}->{'Tool'} eq "mincdiffusion")) {
    print LOG "\n$Usage\nERROR:\n\tYou must specify which version of mincdiffusion tools was used to post-process the DTI.\n";
    exit 33;
}


    #######################
    ####### Step 2: #######  Extract files that we want to register in the database
    #######################
# 2.a Fetch output path stored in $DTIrefs
my  ($XMLProtocol, $QCReport, $XMLReport, $mri_files)   = &getFiles($dti_file, $DTIrefs, $protXMLrefs);
# 2.b Checks that all required outputs were found (there are already a good level of checking in getFiles)     
# If $QCed_minc is not defined, means that getFiles returned undef for all output files => ERROR.
if  (!$QCReport) {
    print LOG "\nERROR:\n\tSome process files are missing in $DTIPrep_subdir.\n";
    exit 33;
}
# If $QCed2_step is set, QCed2_minc should be defined in %mri_files hash! 
if  (($QCed2_step) && (!$mri_files->{'Preproc'}{'QCed2'}{'minc'})) {
    print LOG "\nERROR:\n\tSecondary QCed DTIPrep nrrd & minc outputs are missing in $DTIPrep_subdir.\n";
    exit 33;
}
# => If we could pass step 2, then all the files to be registered were found in the filesystem!


    #######################
    ####### Step 3: #######  Register the XML report
    #######################
    # $registeredXMLReportFile will store the path to the registered XMLReportFile
my ($registeredXMLReportFile)   = &register_XMLFile($XMLReport, 
                                                    $dti_file, 
                                                    $data_dir,
                                                    $QCReport, 
                                                    $DTIPrepVersion);
if (!$registeredXMLReportFile) {
    print LOG "\nERROR: no XML report file was registered in the database\n";
    exit 0;
} else {
    print LOG "\nRegistered XML report $registeredXMLReportFile.\n";
}


    #######################
    ####### Step 4: #######  Register the QC report
    #######################
    # $registeredQCReportFile will store the path to the registered QCReportFile
my ($registeredQCReportFile)    = &register_QCReport($QCReport, 
                                                     $dti_file, 
                                                     $data_dir,
                                                     $DTIPrepVersion);
if (!$registeredQCReportFile) {
    print LOG "\nERROR: no QC report file was registered in the database\n";
    exit 0;
} else {
    print LOG "\nRegistered QC report $registeredQCReportFile.\n";
}


    #######################
    ####### Step 5: #######  Register the XML protocol file used by DTIPrep
    #######################
    # $registeredXMLprotocolFile will store the path to the registered XMLprotocolFile
my ($registeredXMLprotocolFile) = &register_XMLFile($XMLProtocol, 
                                                    $dti_file, 
                                                    $data_dir,
                                                    $QCReport, 
                                                    $DTIPrepVersion);
if (!$registeredXMLprotocolFile) {
    print LOG "\nERROR: no XML protocol file was registered in the database\n";
    exit 0;
} else {
    print LOG "\nRegistered XML protocol $registeredXMLprotocolFile.\n";
}


    #######################
    ####### Step 6: #######  Register DTIPrep preprocessed minc files with associated reports and nrrd files
    #######################
# Register QCed nrrd followed by QCed minc file (with a link to the QCed nrrd file)
my  ($preproc_registered, 
     $preproc_failed_to_register)   = &register_images($mri_files, 
                                                       $dti_file,
                                                       $data_dir,
                                                       $DTIPrepVersion, 
                                                       $registeredXMLReportFile, 
                                                       $registeredQCReportFile, 
                                                       $registeredXMLprotocolFile,
                                                       'Preproc'
                                                      );



    #######################
    ####### Step 7: #######  Register post processed files
    #######################
# If mincdiffusion tools were used to create post processed files, register $RGB_minc, $FA_minc, $MD_minc, $baseline_minc, $brain_mask_minc files into the database    
my ($pipelineName);
if ($mri_files->{'Postproc'}{'Tool'} eq "mincdiffusion") {
    $pipelineName   = $mincdiffVersion;
} elsif ($mri_files->{'Postproc'}{'Tool'} eq "DTIPrep") {
    $pipelineName   = $DTIPrepVersion;
}

my ($postproc_registered, 
    $postproc_failed_to_register)   = &register_images($mri_files, 
                                                       $dti_file,
                                                       $data_dir,
                                                       $pipelineName, 
                                                       $registeredXMLReportFile, 
                                                       $registeredQCReportFile, 
                                                       $registeredXMLprotocolFile,
                                                       'Postproc'
                                                      );

# Program is finished
exit 0;


#############
# Functions #
#############

=pod
This set the different parameters needed to be able to register minc files. 
Once set, this function will call registerFile which will run the script register_processed_data.pl.
=cut
sub register_minc {
    my ($minc, $raw_file, $data_dir, $pipelineName, $registeredXMLFile, $registeredQCReportFile, $registeredXMLprotocolFile, $scanType, $registered_nrrd)  =   @_;

    print LOG "\n==> File to register is:\n$minc\n";
    print "\n==>File: $minc\n";

    # Determine source file name and source file ID
    my ($src_name)      = basename($raw_file, '.mnc');
    my ($src_fileID)    = &getSourceFileID($minc, $src_name, $dbh);
    
    # Determine pipeline used to create processed data 
    my  ($src_pipeline, $pipelineName_insert);
    if  (!$pipelineName)    {
        # need to develop this later once DTIPrep versioning will be reported into QC reports.
        ($src_pipeline)   =   &getPipelineName($minc);
    } else   {
        $src_pipeline     =   $pipelineName;
        # insert pipelineName into the mincheader if not already in.
        ($pipelineName_insert)   = &DTI::modify_header('processing:pipeline', 
                                                       $src_pipeline, 
                                                       $minc,
                                                       '$3, $4, $5, $6');
        return undef    if (!$pipelineName_insert);
    }
    
    # Determine date at which pipeline was run based on registered QC report file
    my  ($pipelineDate) =   &getPipelineDate($minc, $data_dir, $registeredQCReportFile); # if date not in $minc, use QC report and insert it into the mincheader.
    
    # Insert into the mincheader the QC reports (txt & xml), DTIPrep protocol
    my ($Txtreport_insert, 
        $XMLreport_insert, 
        $protocol_insert)   = &insertReports($minc, 
                                             $registeredXMLFile, 
                                             $registeredQCReportFile, 
                                             $registeredXMLprotocolFile);

    # Insert pipeline summary (how many rejected directions...) into the mincheader
    my ($summary_insert)    = &insertPipelineSummary($minc, $data_dir, $registeredQCReportFile);

    # Insert into the mincheader processed directory of the minc to register
    my $procdir             = dirname($minc);
    my ($procdir_insert)    = &DTI::modify_header('processing:processed_dir', 
                                                  $procdir,
                                                  $minc,
                                                  '$3, $4, $5, $6');

    # Insert nrrd file into minc file if $registered_nrrd is defined
    my ($nrrd_insert)       = &DTI::modify_header('processing:nrrd_file', $registered_nrrd, $minc, '$3, $4, $5, $6')  if ($registered_nrrd);
    
    # Determine coordinate space
    my ($coordinateSpace);
    $coordinateSpace = "native"      if ($pipelineName =~ /DTIPrep/i);
    $coordinateSpace = "nativeT1"    if ($pipelineName =~ /mincdiffusion/i);

    # Determine output type
    my $outputType  =   "qc";

    # Check is all information was correctly inserted into the minc file
    return undef    unless (($Txtreport_insert) && ($XMLreport_insert) 
                         && ($protocol_insert)  && ($nrrd_insert)
                         && ($summary_insert)   && ($pipelineName_insert)
                         && ($procdir_insert));
    # Return undef if a nrrd file was registered but not inserted into the mincheader of the associated minc
    return undef    if (($registered_nrrd) && (!$nrrd_insert));

    # If all necessary information are defined, register the file. Return undef otherwise
    if  (($minc)            &&  ($src_fileID)      && 
         ($src_pipeline)    &&  ($pipelineDate)    && 
         ($coordinateSpace) &&  ($scanType)        && 
         ($outputType))     { 

        my  ($registeredMincFile)   = &registerFile($minc, 
                                        $src_fileID, 
                                        $src_pipeline, 
                                        $pipelineDate, 
                                        $coordinateSpace, 
                                        $scanType, 
                                        $outputType); 
        
        return ($registeredMincFile);

    } else {

        print LOG "\nERROR: a required option for register_processed_data.pl is not set!!\n";
        print LOG "sourceFileID:    $src_fileID\n"      .
                  "sourcePipeline:  $src_pipeline\n"    .
                  "pipelineDate:    $pipelineDate\n"    .
                  "coordinateSpace: $coordinateSpace\n" .
                  "scanType:        $scanType\n"        .
                  "outputType:      $outputType\n";

        return undef;
    }    

}   

=pod
This set the different parameters needed to be able to register XML Report and protocol of DTIPrep. 
Once set, this function will call registerFile which will run register_processed_data.pl.
=cut
sub register_XMLFile {
    my ($XMLFile, $raw_file, $data_dir, $QCReport, $pipelineName) =   @_;

    print LOG "\n==> File to register is:\n$XMLFile\n";
    print "\n==>File: $XMLFile\n";

    my  $src_name   = basename($raw_file, '.mnc');
    my  $src_fileID = &getSourceFileID($XMLFile, $src_name, $dbh);

    my  $src_pipeline;
    if  (!$pipelineName)    {
        print "WARNING: This should not happen as long as the pipeline versioning of DTIPrep is not fixed!"; 
        exit 33; 
        # Will need to program this part once DTIPrep fixed!
        #($src_pipeline)=getPipelineName($XMLFile);
    }else   {
        $src_pipeline   =   $pipelineName;
    }

    my ($pipelineDate)  =   &getPipelineDate($XMLFile, $data_dir, $QCReport);

    my $coordinateSpace =   "native";
    my ($scanType, $outputType);
    if ($XMLFile =~ /XMLQCResult\.xml$/i) {
        $scanType       =   "DTIPrepXMLReport";
        $outputType     =   "qcreport";
    } elsif ($XMLFile =~ /DTIPrepProtocol\.xml$/i) {
        $scanType       =   "DTIPrepProtocol";
        $outputType     =   "protocol";
    }
    # register file if all information are available
    if  (($XMLFile)         &&  ($src_fileID)      &&
         ($src_pipeline)    &&  ($pipelineDate)    &&
         ($coordinateSpace) &&  ($scanType)        &&
         ($outputType))     {

        my  ($registeredXMLFile)  = registerFile($XMLFile,
                                        $src_fileID,
                                        $src_pipeline,
                                        $pipelineDate,
                                        $coordinateSpace,
                                        $scanType,
                                        $outputType);

        return ($registeredXMLFile);

    } else {

        print LOG "\nERROR: a required option for register_processed_data.pl is not set!!\n";
        print LOG "sourceFileID:    $src_fileID\n"      .
                  "sourcePipeline:  $src_pipeline\n"    .
                  "pipelineDate:    $pipelineDate\n"    .
                  "coordinateSpace: $coordinateSpace\n" .
                  "scanType:        $scanType\n"        .
                  "outputType:      $outputType\n";
        return undef;

    }
}        

=pod
This set the different parameters needed to be able to register QCReports of DTIPrep. 
Once set, this function will call registerFile which will run register_processed_data.pl.
=cut
sub register_QCReport {
    my ($QCReport, $raw_file, $data_dir, $pipelineName)    =   @_;

    print LOG "\n==> File to register is:\n$QCReport\n";
    print "\n==>File: $QCReport\n";

    my  $src_name   = basename($raw_file, '.mnc');
    my  $src_fileID = &getSourceFileID($QCReport,$src_name,$dbh);

    my  $src_pipeline;
    if  (!$pipelineName)    {
        print "WARNING: This should not happen as long as the pipeline versioning of DTIPrep is not fixed!"; 
        exit 33; 
        # Will need to program this part once DTIPrep fixed!
        #($src_pipeline)=getPipelineName($QCReport);
    }else   {
        $src_pipeline =   $pipelineName;
    }

    my ($pipelineDate)  =   &getPipelineDate($QCReport, $data_dir, $QCReport);

    my $coordinateSpace =   "native";
    my $scanType        =   "DTIPrepTxtReport";
    my $outputType      =   "qcreport";

    if  (($QCReport)        &&  ($src_fileID)      &&
         ($src_pipeline)    &&  ($pipelineDate)    &&
         ($coordinateSpace) &&  ($scanType)        &&
         ($outputType))     {

        my  ($registeredQCReportFile) = registerFile($QCReport,
                                            $src_fileID,
                                            $src_pipeline,
                                            $pipelineDate,
                                            $coordinateSpace,
                                            $scanType,
                                            $outputType);

        return ($registeredQCReportFile);
    
    } else {
    
        print LOG "\nERROR: a required option for register_processed_data.pl is not set!!\n";
        print LOG "sourceFileID:    $src_fileID\n"      .
                  "sourcePipeline:  $src_pipeline\n"    .
                  "pipelineDate:    $pipelineDate\n"    . 
                  "coordinateSpace: $coordinateSpace\n" .
                  "scanType:        $scanType\n"        . 
                  "outputType:      $outputType\n";
        return undef;
        
    }

}        
        
=pod
This function checks that all the processing files exist on the filesystem and returns the files to be inserted in the database. When nrrd and minc files were found, it will only return the minc file. (nrrd files will be linked to the minc file when inserting files in the database).
- Inputs:   - $dti_file = raw DTI dataset that is used as a key in $DTIrefs hash
            - $DTIrefs      = hash containing all output paths and tool information
- Outputs:  - if all files have been found on the file system, will return:
                - ($XMLProtocol, $QCReport, $XMLReport, $QCed_minc, $RGB_minc, $FA_minc, $MD_minc, $baseline_minc, $brain_mask_minc, $QCed2_minc)
            - if there are some missing files, it will return undef 
=cut
sub getFiles {
    my ($dti_file, $DTIrefs)   =   @_;

    my (%mri_files);
    # DTIPrep preprocessing files to be registered
    my ($XMLProtocol, $QCReport, $XMLReport)= &checkPreprocessFiles($dti_file, $DTIrefs, \%mri_files);
    # Post processing files to be registered
    my ($all_processed_found)               = &checkPostprocessFiles($dti_file, $DTIrefs, \%mri_files);

    # return all output files if one preprocessed output and one postprocess output are defined. Will return undef otherwise
    if (($QCReport) && ($all_processed_found)) {
        return  ($XMLProtocol, $QCReport, $XMLReport, \%mri_files);
    } else {
        return undef;
    }
}

=pod
Function that checks if all DTIPrep preprocessing files are present in the file system.
- Inputs:   - $dti_file     = raw DTI dataset that is used as a key in $DTIrefs hash
            - $DTIrefs      = hash containing all output paths and tool information
- Outputs:  - $XMLProtocol  = DTIPrep XML protocol that was found in the file system
            - $QCReport     = DTIPrep Txt QCReport that was found in the file system
            - $XMLReport    = DTIPrep XML QCReport that was found in the file system
            - $QCed_minc    = QCed minc file that was created after conversion of QCed DTIPrep nrrd file
            - $QCed2_minc   = Optionally, secondary QCed minc file that was created after conversion of secondary QCed DTIPrep nrrd file 
            - return undef if one of the file listed above is missing (except for QCed2_minc which is optional)
=cut
sub checkPreprocessFiles {
    my  ($dti_file, $DTIrefs, $mri_files) = @_;

    # Store tool used for Preprocessing in %mri_files
    $mri_files->{'Preproc'}{'Tool'}    = "DTIPrep";

    # Determine file path of each output
    my  $XMLProtocol=   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCProt'};
    my  $QCReport   =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCTxtReport'};
    my  $XMLReport  =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCXmlReport'};
    my  $QCed_nrrd  =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed_nrrd'};
    my  $QCed_minc  =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed_minc'};
    my  $QCed2_nrrd =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed2_nrrd'};
    my  $QCed2_minc =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed2_minc'};

    # Check that all outputs exist in the filesystem and return them (except the nrrd ones).
    if ((-e $XMLProtocol) && (-e $QCReport) && (-e $XMLReport) && (-e $QCed_nrrd) && (-e $QCed_minc)) {

        $mri_files->{'Preproc'}{'QCed'}{'nrrd'}      = $QCed_nrrd;
        $mri_files->{'Preproc'}{'QCed'}{'minc'}      = $QCed_minc;
        $mri_files->{'Preproc'}{'QCed'}{'scanType'}  = 'QCedDTI';
        $mri_files->{'Preproc'}{'QCed2'}{'nrrd'}     = $QCed2_nrrd;
        $mri_files->{'Preproc'}{'QCed2'}{'minc'}     = $QCed2_minc;
        $mri_files->{'Preproc'}{'QCed2'}{'scanType'} = 'noRegQCedDTI';
        return ($XMLProtocol, $QCReport, $XMLReport);

    } else {

        print LOG "DTIPrep preprocessing outputs were not all found in the filesystem.\n";
        return undef;

    }
}






=pod
Function that checks if all postprocessing files (from DTIPrep or mincdiffusion) are present in the file system.
- Inputs:   - $dti_file     = raw DTI dataset that is used as a key in $DTIrefs hash
            - $DTIrefs      = hash containing all output paths and tool information
- Outputs:  - if mincdiffusion was run and found all outputs on the filesystem, will return:
                - $RGB_minc         = RGB map
                - $FA_minc          = FA map
                - $MD_minc          = MD map
                - $baseline_minc    = baseline (or frame-0) map
                - $brain_mask_minc  = brain mask produced by mincdiffusion tools
            - if DTIPrep was run and found all postprocessed outputs (nrrd & minc) on the filesystem, will return:
                - $RGB_minc         = RGB map
                - $FA_minc          = FA map
                - $MD_minc          = MD map
                - $baseline_minc    = baseline (or frame-0) map
            - will return undef and print messages into the LOG file otherwise 
=cut
sub checkPostprocessFiles {
    my ($dti_file, $DTIrefs, $mri_files) = @_;

    # Determine file path of each postprocessed outputs common to the two tools (DTIPrep & mincdiffusion)
    my  $RGB_minc       =   $DTIrefs->{$dti_file}->{'Postproc'}->{'RGB_minc'}; 
    my  $FA_minc        =   $DTIrefs->{$dti_file}->{'Postproc'}->{'FA_minc'};
    my  $MD_minc        =   $DTIrefs->{$dti_file}->{'Postproc'}->{'MD_minc'};
    my  $baseline_minc  =   $DTIrefs->{$dti_file}->{'Postproc'}->{'baseline_minc'};

    if ((-e $RGB_minc) && (-e $FA_minc) && (-e $MD_minc) && (-e $baseline_minc)) {
        $mri_files->{'Postproc'}{'RGB'}{'minc'}         = $RGB_minc;
        $mri_files->{'Postproc'}{'RGB'}{'scanType'}     = 'RGBqc';
        $mri_files->{'Postproc'}{'FA'}{'minc'}          = $FA_minc;
        $mri_files->{'Postproc'}{'FA'}{'scanType'}      = 'FAqc';
        $mri_files->{'Postproc'}{'MD'}{'minc'}          = $MD_minc;
        $mri_files->{'Postproc'}{'MD'}{'scanType'}      = 'MDqc';
        $mri_files->{'Postproc'}{'baseline'}{'minc'}    = $baseline_minc;
        $mri_files->{'Postproc'}{'baseline'}{'scanType'}= 'DTIb0qc';
    } else {
        print LOG "Could not find postprocessing minc files on the filesystem.\n";
        return undef;
    }

    # Check which tool has been used to post process DTI dataset to validate that all outputs are found in the filsystem
    my  ($RGB_nrrd, $FA_nrrd, $MD_nrrd, $baseline_nrrd, $brain_mask_minc);
    if ($DTIrefs->{$dti_file}->{'Postproc'}->{'Tool'} eq "DTIPrep") {

        # Store tool used for Postprocessing in %mri_files
        $mri_files->{'Postproc'}{'Tool'}    = "DTIPrep";

        # Fetches info about DTIPrep nrrd post processing files
        $RGB_nrrd       =   $DTIrefs->{$dti_file}->{'Postproc'}->{'RGB_nrrd'}; 
        $FA_nrrd        =   $DTIrefs->{$dti_file}->{'Postproc'}->{'FA_nrrd'};
        $MD_nrrd        =   $DTIrefs->{$dti_file}->{'Postproc'}->{'MD_nrrd'};
        $baseline_nrrd  =   $DTIrefs->{$dti_file}->{'Postproc'}->{'baseline_nrrd'};

        # Return minc files if all nrrd and minc outputs exist on the filesystem
        if ((-e $RGB_nrrd) && (-e $FA_nrrd) && (-e $MD_nrrd) && (-e $baseline_nrrd)) {
            $mri_files->{'Postproc'}{'RGB'}{'nrrd'}         = $RGB_nrrd;
            $mri_files->{'Postproc'}{'FA'}{'nrrd'}          = $FA_nrrd;
            $mri_files->{'Postproc'}{'MD'}{'nrrd'}          = $MD_nrrd;
            $mri_files->{'Postproc'}{'baseline'}{'nrrd'}    = $baseline_nrrd;
            return 1;
        } else {
            print LOG "Could not find all DTIPrep postprocessing outputs on the filesystem.\n";
            return undef;
        }

    } elsif ($DTIrefs->{$dti_file}->{'Postproc'}->{'Tool'} eq "mincdiffusion") {

        # Store tool used for Postprocessing in %mri_files
        $mri_files->{'Postproc'}{'Tool'}    = "mincdiffusion";

        # Extract brain mask used by the diffusion tools
        $brain_mask_minc=   $DTIrefs->{$dti_file}->{'Postproc'}->{'anat_mask_diff_minc'};
        # Return minc files if all minc outputs exist on the filesystem
        if (-e $brain_mask_minc) {
            $mri_files->{'Postproc'}{'mask'}{'minc'}    = $brain_mask_minc;
            $mri_files->{'Postproc'}{'mask'}{'scanType'}= 'DTImaskqc';
            return 1;
        } else {
            print LOG "Could not find all mincdiffusion outputs on the filesystem.\n";
            return undef;
        }

    } else {

        print LOG "Could not identify which post-processing tool was used to process DWI files\n.";
        return undef;

    }
}










=pod
Fetches the source FileID from the database based on the src_name file identified by getSourceFileName.
=cut
sub getSourceFileID {
    my  ($file, $src_name, $dbh) = @_;

    my $fileID;

    # fetch the FileID of the raw dataset
    my $query   =   "SELECT FileID " .
                    "FROM files " . 
                    "WHERE File like ?";
    
    my $like    =   "%$src_name%";    
    my $sth     =   $dbh->prepare($query); 
    $sth->execute($like);
    
    if  ($sth->rows > 0)    {
        my $row =   $sth->fetchrow_hashref();
        $fileID =   $row->{'FileID'};
    }else   {
        print LOG "WARNING: No fileID matches the raw dataset $src_name used to produce $file.\n\n\n";
    }
    
    return  ($fileID);
}

=pod
Fetches pipeline informations in the header of the minc files or in the QCReport.
=cut
sub getPipelineName {    
    my  ($file)     =   @_;

    my  $src_pipeline   =   DTI::fetch_header_info('processing:pipeline',
                                                   $file,
                                                   '$3');
    if  (!$src_pipeline)  {
        print LOG "ERROR: no pipeline have been found in mincheader of $file. Check that the processing:pipeline field exits or specify which pipeline was used manually with the option -pipelineName as input of the script DTIPrepRegister.pl."; 
        exit 33;
    }else   {
        #remove leading spaces, trailing spaces and all instances of "
        $src_pipeline   =~s/"//g;
    }
    
    return  ($src_pipeline);
}

=pod
This function fetches the date at which DTIPrep pipeline was run either in the mincheader of the processed file or in the QCReport file.
=cut
sub getPipelineDate {
    my  ($file, $data_dir, $QCReport)   =   @_;
    
    # Remove $data_dir path from $QCReport in the case it is included in the path
    $QCReport =~ s/$data_dir//i;

    my  ($pipelineDate, $date_insert);
    
    if  ($file=~/\.mnc/)    {
        $pipelineDate   = &DTI::fetch_header_info('processing:processing_date',
                                                  $file,
                                                  '$3');
    }
    
    if  (!$pipelineDate)   {
    
        print LOG "\n> Fetching date of processing in the QCReport.txt file created by DTIPrep";
        my  $check_line = `cat $data_dir/$QCReport|grep "Check Time"`;
        $check_line     =~s/Check Time://i;      # Only keep date info in $check_line.
        #use Date::Parse library to read the date
        my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($check_line);
        $pipelineDate   =  sprintf("%4d%02d%02d", $year+1900, $month+1, $day);
        
        if ($file=~/\.mnc/) {
            # insert pipelineDate into mincheader if not already in the mincheader. 
            ($date_insert)  = &DTI::modify_header('processing:processing_date', 
                                                  $pipelineDate, 
                                                  $file,
                                                  '$3, $4, $5, $6');
        }
    
    } else  {
        
        print LOG "\n> Fetching date of processing in the mincheader of $file";
        #remove leading spaces, trailing spaces and all instances of "
        $pipelineDate   =~s/"//g;
        $date_insert    = "already inserted";
    
    }
    
    # if date was not inserted into the mincheader, return undef
    return undef    if (($file=~/\.mnc/) && (!$date_insert));   
    # return pipeline date otherwise
    return  ($pipelineDate);
}

=pod
Insert in the mincheader the path to DTIPrep QC txt and xml reports.
=cut
sub insertReports {
    my ($minc, $registeredXMLFile, $registeredQCReportFile, $registeredXMLprotocolFile) = @_;

    # Return undef if there is at least one missing function argument
    return undef    unless (($minc) && ($registeredXMLFile) && ($registeredQCReportFile) && ($registeredXMLprotocolFile));

    # Insert files into the mincheader
    my ($Txtreport_insert)  = &DTI::modify_header('processing:DTIPrepTxtReport',
                                                  $registeredQCReportFile,     
                                                  $minc,
                                                  '$3, $4, $5, $6');
    my ($XMLreport_insert)  = &DTI::modify_header('processing:DTIPrepXmlReport',
                                                  $registeredXMLFile, 
                                                  $minc,
                                                  '$3, $4, $5, $6');
    my ($protocol_insert)   = &DTI::modify_header('processing:DTIPrepXmlProtocol', 
                                                  $registeredXMLprotocolFile,  
                                                  $minc,
                                                  '$3, $4, $5, $6');

    return ($Txtreport_insert, $XMLreport_insert, $protocol_insert);
}

=pod
Insert in the mincheader the summary of DTIPrep reports.
=cut
sub insertPipelineSummary   {
    my ($minc, $data_dir, $QCReport)   =   @_;

    my ($rm_slicewise,
        $rm_interlace,
        $rm_intergradient)  =   &getRejectedDirections($data_dir, $QCReport);
    
    my ($count_slice, $insert_slice)        = &insertHeader($minc, $rm_slicewise,      "processing:slicewise_rejected");
    my ($count_inter, $insert_inter)        = &insertHeader($minc, $rm_interlace,      "processing:interlace_rejected");
    my ($count_gradient, $insert_gradient)  = &insertHeader($minc, $rm_intergradient,  "processing:intergradient_rejected");

    my ($total)         = $count_slice + $count_inter + $count_gradient;
    my ($total_insert)  = &DTI::modify_header('processing:total_rejected', 
                                              $total, 
                                              $minc,
                                              '$3, $4, $5, $6');
    # If all insertions went well, return 1, otherwise return undef
    if (($total_insert) && ($insert_slice) && ($insert_inter) && ($insert_gradient)) {
        return 1;
    } else {
        return undef;
    }
}

=pod
Get the list of directions rejected by DTI per type (i.e. slice-wise correlations, inter-lace artifacts, inter-gradient artifacts).
=cut
sub getRejectedDirections   {
    my ($data_dir, $QCReport)  =   @_;

    # Remove $data_dir path from $QCReport in the case it is included in the path
    $QCReport =~ s/$data_dir//i;

    ## these are the unique directions that were rejected due to slice-wise correlations
    my $rm_slicewise    =   `cat $data_dir/$QCReport | grep whole | sort -k 2,2 -u | awk '{print \$2}'|tr '\n' ','`;
    ## these are the unique directions that were rejected due to inter-lace artifacts
    my $rm_interlace    =   `cat $data_dir/$QCReport | sed -n -e '/Interlace-wise Check Artifacts/,/================================/p' | grep '[0-9]' | sort -k 1,1 -u | awk '{print \$1}'|tr '\n' ','`;
    ## these are the unique directions that were rejected due to inter-gradient artifacts
    my $rm_intergradient=   `cat $data_dir/$QCReport | sed -n -e '/Inter-gradient check Artifacts::/,/================================/p' | grep '[0-9]'| sort -k 1,1 -u  | awk '{print \$1}'|tr '\n' ','`;
    
    return ($rm_slicewise,$rm_interlace,$rm_intergradient);
}

=sub
Insert into the minc header the directions rejected due to a specific artifact.
=cut
sub insertHeader    {
    my ($minc,$rm_directions,$minc_field)    =   @_;

    my @rm_dirs     =   split(',',$rm_directions);
    my $count_dirs  =   scalar(@rm_dirs);

    my  $value;
    if  ($count_dirs==0)    {
        $value  =   "\"@rm_dirs ($count_dirs)\"";
    } else  {
        $value  =   "\"Directions @rm_dirs ($count_dirs)\"";
    }    
    
    my ($insert)    = &DTI::modify_header($minc_field, $value, $minc, '$3, $4, $5, $6');

    if ($insert) {
        return  ($count_dirs, "success");
    } else {
        return undef;
    }
}

=pod
Runs register_processed_data.pl on file.
=cut
sub registerFile  {
    my  ($file, $src_fileID, $src_pipeline, $pipelineDate, $coordinateSpace, $scanType, $outputType)    =   @_;

    print LOG "\n\t- sourceFileID is: $src_fileID\n";
    print LOG "\t- src_pipeline is: $src_pipeline\n";
    print LOG "\t- pipelineDate is: $pipelineDate\n";
    print LOG "\t- coordinateSpace is: $coordinateSpace\n";
    print LOG "\t- scanType is: $scanType\n";
    print LOG "\t- outputType is: $outputType\n";
    my $cmd =   "perl ../uploadNeuroDB/register_processed_data.pl " .
                    "-profile $profile " .
                    "-file $file " .
                    "-sourceFileID $src_fileID " .
                    "-sourcePipeline $src_pipeline " .
                    "-pipelineDate $pipelineDate " .
                    "-coordinateSpace $coordinateSpace " .
                    "-scanType $scanType " .
                    "-outputType $outputType";
    system($cmd);
    print LOG "\n==> Command sent:\n$cmd\n";
    
    my  ($registeredFile) = fetchRegisteredFile($src_fileID, $src_pipeline, $pipelineDate, $coordinateSpace, $scanType, $outputType);

    return ($registeredFile);
}        

=pod
Fetch the registered report fileID to link it to the minc files
=cut
sub fetchRegisteredFile {
    my ($src_fileID, $src_pipeline, $pipelineDate, $coordinateSpace, $scanType, $outputType) = @_;

    my $registeredFile;

    # fetch the FileID of the raw dataset
    my $query   =   "SELECT f.File "          .
                    "FROM files f "             .
                    "JOIN mri_scan_type mst "   .
                        "ON mst.ID=f.AcquisitionProtocolID ".
                    "WHERE f.SourceFileID=? "   .
                        "AND f.SourcePipeline=? "   .
                        "AND f.PipelineDate=? "     .
                        "AND f.CoordinateSpace=? "  .
                        "AND mst.Scan_type=? "      .
                        "AND OutputType=?";

    my $sth     =   $dbh->prepare($query);
    $sth->execute($src_fileID, $src_pipeline, $pipelineDate, $coordinateSpace, $scanType, $outputType);

    if  ($sth->rows > 0)    {
        my $row =   $sth->fetchrow_hashref();
        $registeredFile =   $row->{'File'};
    }else   {
        print LOG "WARNING: No fileID found for SourceFileID=$src_fileID, SourcePipeline=$src_pipeline, PipelineDate=$pipelineDate, CoordinateSpace=$coordinateSpace, ScanType=$scanType and OutputType=$outputType.\n\n\n";
    }

    return  ($registeredFile);

}







#=pod
#Register mincdiffusion outputs (RGB, FA, MD, Baseline and Brain mask files) into the database with links to DTIPrep QC reports (Txt & XML) and DTIPrep XML protocol used.
#- Inputs:   - files to be registered ($RGB_minc, $FA_minc, $MD_minc, $baseline_minc and $brain_mask_minc)
#            - QC report files registered in the database ($registeredXMLReportFile, $registeredQCReportFile)
#            - XML protocol used by DTIPrep ($registeredXMLprotocolFile)
#            - Txt report
#=cut
#sub register_mincdiff_files {
#    my ($mri_files, $mincdiffVersion, $registeredXMLReportFile, $registeredQCReportFile, $registeredXMLprotocolFile) = @_;
#
#    # Return undef if variables given as arguments are not defined
#    return undef    unless (($mri_files)                && ($mincdiffVersion) 
#                         && ($registeredXMLReportFile)  && ($registeredQCReportFile)  
#                         && ($registeredXMLprotocolFile));
#
#    foreach my $preproc_file (keys($mri_files->{$process_step})) {
#
#        # register file into the database
#        my $minc    = $mri_files->{$process_step}{$preproc_file}{'minc'};
#        my $scanType= $mri_files->{$process_step}{$preproc_file}{'scanType'};
#        my ($registered_file)   = &register_minc($minc,
#                                                 $mincdiffVersion, 
#                                                 $registeredXMLReportFile,
#                                                 $registeredQCReportFile,
#                                                 $registeredXMLprotocolFile,
#                                                 $scanType
#                                                );
#
#        # push into array registered the registered file
#        push(@registered, $registered_file)         if ($registered_file);
#        push(@failed_to_register, $registered_file) if (!$registered_file);
#    
#    }
#
#    # Return registered files and unregistered files
#    return (\@registered, \@failed_to_register);
#
#}









=pod
Register DTIPrep nrrd and minc files. The minc file will have a link to the registered nrrd file (register_minc function will modify mincheader to include this information) in addition to the links toward QC reports and protocol.
- Inputs:   - files to be registered ($minc, $nrrd)
            - registered QC report files ($registeredXMLReportFile, $registeredQCReportFile)
            - registered DTIPrep XML protocol ($registeredXMLprotocolFile)
            - $DTIPrepVersion used to produce the files
- Outputs:  - registered minc files if the nrrd and minc files were successfully registered in the database
            - undef if one argument of the function if missing or if nrrd file could not be registered
=cut
sub register_DTIPrep_files {
    my  ($minc, $nrrd, $raw_file, $data_dir, $DTIPrepVersion, $registeredXMLReportFile, $registeredQCReportFile, $registeredXMLprotocolFile, $scanType) = @_;

    # Return undef if variables given as arguments are not defined
    return undef    unless (($minc)                    && ($nrrd)                  
                         && ($DTIPrepVersion)          && ($registeredXMLReportFile) 
                         && ($registeredQCReportFile)  && ($registeredXMLprotocolFile));

    # Register nrrd file into the database
    my ($registered_nrrd)   = &register_nrrd($nrrd,
                                             $raw_file,
                                             $data_dir,
                                             $registeredQCReportFile,
                                             $DTIPrepVersion,
                                             $scanType
                                            );
    return undef    if (!$registered_nrrd);

    # Register minc file into the database with link to the QC reports, protocol and registered nrrd
    my ($registered_minc)   = &register_minc($minc,
                                             $raw_file,
                                             $data_dir,
                                             $DTIPrepVersion,
                                             $registeredXMLReportFile,
                                             $registeredQCReportFile,
                                             $registeredXMLprotocolFile,
                                             $scanType,
                                             $registered_nrrd
                                            );

    # Return registered minc file
    return $registered_minc;
}



=pod
This set the different parameters needed to be able to register XML Report and protocol of DTIPrep. 
Once set, this function will call registerFile which will run register_processed_data.pl.
=cut
sub register_nrrd {
    my ($nrrd, $raw_file, $data_dir, $QCReport, $pipelineName, $scanType) =   @_;

    print LOG "\n==> File to register is:\n$nrrd\n";
    print "\n==>File: $nrrd\n";

    my  $src_name   = basename($raw_file, '.mnc');
    my  $src_fileID = &getSourceFileID($nrrd, $src_name, $dbh);

    my  $src_pipeline;
    if  (!$pipelineName)    {
        print "WARNING: This should not happen as long as the pipeline versioning of DTIPrep is not fixed!";
        exit 33;
        # Will need to program this part once DTIPrep fixed!
        #($src_pipeline)=getPipelineName($XMLFile);
    }else   {
        $src_pipeline   =   $pipelineName;
    }

    my ($pipelineDate)  =   &getPipelineDate($nrrd, $data_dir, $QCReport);

    my ($coordinateSpace);
    $coordinateSpace = "native"      if ($pipelineName =~ /DTIPrep/i);
    $coordinateSpace = "nativeT1"    if ($pipelineName =~ /mincdiffusion/i);

    my $outputType      =   "qc";

    # register file if all information are available
    if  (($nrrd)            &&  ($src_fileID)      &&
         ($src_pipeline)    &&  ($pipelineDate)    &&
         ($coordinateSpace) &&  ($scanType)        &&
         ($outputType))     {

        my  ($registeredNrrdFile)  = registerFile($nrrd,
                                        $src_fileID,
                                        $src_pipeline,
                                        $pipelineDate,
                                        $coordinateSpace,
                                        $scanType,
                                        $outputType);

        return ($registeredNrrdFile);

    } else {

        print LOG "\nERROR: a required option for register_processed_data.pl is not set!!\n";
        print LOG "sourceFileID:    $src_fileID\n"      .
                  "sourcePipeline:  $src_pipeline\n"    .
                  "pipelineDate:    $pipelineDate\n"    .
                  "coordinateSpace: $coordinateSpace\n" .
                  "scanType:        $scanType\n"        .
                  "outputType:      $outputType\n";

        return undef;

    }
}   


#sub register_DTIPrep_postproc {
#    my ($mri_files, $DTIPrepVersion, $registeredXMLReportFile, $registeredQCReportFile, $registeredXMLprotocolFile) = @_;
#
#    return undef    unless (($mri_files)                && ($DTIPrepVersion)           
#                         && ($registeredXMLReportFile)  && ($registeredQCReportFile)   
#                         && ($registeredXMLprotocolFile));
#
#
#    # register DTIPrep RGB map
#    my  ($registeredRGB)    = &register_DTIPrep_files($mri_files->{'RGB'}{'minc'}, 
#                                                      $mri_files->{'RGB'}{'nrrd'},
#                                                      $DTIPrepVersion, 
#                                                      $registeredXMLReportFile, 
#                                                      $registeredQCReportFile, 
#                                                      $registeredXMLprotocolFile,
#                                                      'RGBqc' 
#                                                     );
#
#    # register DTIPrep FA map 
#    my  ($registeredFA)     = &register_DTIPrep_files($mri_files->{'FA'}{'minc'}, 
#                                                      $mri_files->{'FA'}{'nrrd'},
#                                                      $DTIPrepVersion, 
#                                                      $registeredXMLReportFile, 
#                                                      $registeredQCReportFile, 
#                                                      $registeredXMLprotocolFile,
#                                                      'FAqc' 
#                                                     );
#
#    # register DTIPrep MD map 
#    my  ($registeredMD)     = &register_DTIPrep_files($mri_files->{'MD'}{'minc'}, 
#                                                      $mri_files->{'MD'}{'nrrd'},
#                                                      $DTIPrepVersion, 
#                                                      $registeredXMLReportFile, 
#                                                      $registeredQCReportFile, 
#                                                      $registeredXMLprotocolFile,
#                                                      'MDqc' 
#                                                     );
#
#
#    # register DTIPrep baseline (or b0, frame-0) map 
#    my  ($registered_b0)    = &register_DTIPrep_files($mri_files->{'baseline'}{'minc'}, 
#                                                      $mri_files->{'baseline'}{'nrrd'},
#                                                      $DTIPrepVersion, 
#                                                      $registeredXMLReportFile, 
#                                                      $registeredQCReportFile, 
#                                                      $registeredXMLprotocolFile,
#                                                      'DTIb0qc' 
#                                                     );
#
#    return ($registeredRGB, $registeredFA, $registeredMD, $registered_b0);
#
#}






sub register_images {
    my ($mri_files, $raw_file, $data_dir, $pipelineName, $registeredXMLReportFile, $registeredQCReportFile, $registeredXMLprotocolFile, $process_step) = @_;

    my (@registered, @failed_to_register, $registered_file);
    foreach my $preproc_file (keys($mri_files->{$process_step})) {

        # Don't register key that is Tool (stores tool used for processing)
        next    if ($preproc_file eq "Tool");

        # register file into the database
        my $minc    = $mri_files->{$process_step}{$preproc_file}{'minc'};
        my $scanType= $mri_files->{$process_step}{$preproc_file}{'scanType'};
        if ($mri_files->{$process_step}{'Tool'} eq "DTIPrep") {

            my $nrrd    = $mri_files->{$process_step}{$preproc_file}{'nrrd'};
            ($registered_file)   = &register_DTIPrep_files($minc,
                                                           $nrrd,
                                                           $raw_file,
                                                           $data_dir,
                                                           $pipelineName, 
                                                           $registeredXMLReportFile, 
                                                           $registeredQCReportFile, 
                                                           $registeredXMLprotocolFile, 
                                                           $scanType
                                                          );

        } elsif ($mri_files->{$process_step}{'Tool'} eq "mincdiffusion") {

            ($registered_file)   = &register_minc($minc,
                                                  $raw_file,
                                                  $data_dir,
                                                  $pipelineName,
                                                  $registeredXMLReportFile,
                                                  $registeredQCReportFile,
                                                  $registeredXMLprotocolFile,
                                                  $scanType
                                                 );


        }

        # push into array registered the registered file
        push(@registered, $registered_file)         if ($registered_file);
        push(@failed_to_register, $registered_file) if (!$registered_file);
    }
    
    return (\@registered, \@failed_to_register);
}

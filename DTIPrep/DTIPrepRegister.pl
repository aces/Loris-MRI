#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use FindBin;
use Date::Parse;
use XML::Simple;
use lib "$FindBin::Bin";

# These are to load the DTI & DBI modules to be used
use DB::DBI;
use DTI::DTI;

# Set default option values
my $profile         = undef;
my $DTIPrep_subdir  = undef;
my $anat            = undef;
my $dti_file        = undef;
my $DTIPrepProtocol = undef;
my $DTIPrepVersion  = undef;
my $mincdiffVersion = undef;
my @args;

# Set the help section
my  $Usage  =   <<USAGE;

Register DTI_QC pipeline's output files of interest into the database via register_processed_data.pl.

The following output files will be considered:
    - QCed minc file produced by DTIPrep preprocessing step (i.e. DTI dataset without the bad directions detected by DTIPrep)
    - QCReport produced by DTPrep
    - XMLQCResult produced by DTIPrep 
    - RGB map produced by either DTIPrep or mincdiffusion post-processing (for visually of color artefact)
    - MD map produced by either DTIPrep or mincdiffusion post-processing
    - FA map produced by either DTIPrep or mincdiffusion post-processing
    - baseline image produced by DTIPrep or mincdiffusion post-processing 
    - DTI mask produced by mincdiffusion post-processing (if mincdiffusion was used to post-process the data)

Usage: $0 [options]

-help for options

USAGE

# Define the table describing the command-line options
my  @args_table = (
    ["-profile",              "string", 1,  \$profile,          "name of the config file in ../dicom-archive/.loris_mri."],
    ["-DTIPrep_subdir",       "string", 1,  \$DTIPrep_subdir,   "DTIPrep subdirectory storing the processed files to be registered"],
    ["-DTIPrepProtocol",      "string", 1,  \$DTIPrepProtocol,  "DTIPrep protocol used to obtain the output files"],
    ["-DTI_file",             "string", 1,  \$dti_file,         "Native DWI dataset used to obtain the output files"],
    ["-anat_file",            "string", 1,  \$anat,             "Native anatomical dataset used to create FA, RGB and other post-processed maps using mincdiffusion tools"],
    ["-DTIPrepVersion",       "string", 1,  \$DTIPrepVersion,   "DTIPrep version used if cannot be found in minc files's processing:pipeline header field."],
    ["-mincdiffusionVersion", "string", 1,  \$mincdiffVersion,  "mincdiffusion release version used if cannot be found in minc files's processing:pipeline header field."]
);

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args) || exit 1;

# input option error checking
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if  ($profile && !defined @Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; 
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



# Needed for log file
my  $data_dir    =  $Settings::data_dir;
my  $log_dir     =  "$data_dir/logs/DTIPrep_register";
system("mkdir -p -m 770 $log_dir") unless (-e $log_dir);
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my  $date        =  sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log         =  "$log_dir/DTIregister$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";



# Fetch DTIPrep step during which a secondary QCed file will be created (for example: noMC for a file without motion correction). 
# This is set as a config option in the config file.
my  $QCed2_step =  $Settings::QCed2_step;



# Establish database connection
my  $dbh    =   &DB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";

print LOG "\n==> DTI output directory is: $DTIPrep_subdir\n";




    #######################
    ####### Step 1: #######  Get the list of output files
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
    print LOG "\nERROR:\n\tCould not determine a list of outputs for $dti_file.\n";
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
    ####### Step 3: #######  Register the XML protocol file used by DTIPrep
    #######################

# $registeredXMLprotocolID will store the ID to the registered XMLprotocolFile
my ($registeredXMLprotocolID)   = &register_XMLProt($XMLProtocol, 
                                                    $data_dir,
                                                    "DTIPrep");
if (!$registeredXMLprotocolID) {
    print LOG "\nERROR: no XML protocol file was registered in the database\n";
    exit 0;
} else {
    print LOG "\nRegistered XML protocol with ID $registeredXMLprotocolID.\n";
    $mri_files->{'Preproc'}{'QCProt'}{'xml'} = $registeredXMLprotocolID; 
}


    #######################
    ####### Step 4: #######  Register the XML report
    #######################

# $registeredXMLReportFile will store the path to the registered XMLReportFile
my ($report_input_file)         = $DTIrefs->{$dti_file}->{'Preproc'}->{'QCReport'}->{'inputs'}->{'Raw_DWI'};
$report_input_file              =~ s/$data_dir\///;
my ($report_input_fileID)       = &getFileID($XMLReport, $report_input_file);
my ($registeredXMLReportFile)   = &register_XMLFile($XMLReport, 
                                                    $dti_file, 
                                                    $data_dir,
                                                    $QCReport, 
                                                    $report_input_fileID,
                                                    $registeredXMLprotocolID,
                                                    "DTIPrepPipeline",
                                                    $DTIPrepVersion);
if (!$registeredXMLReportFile) {
    print LOG "\nERROR: no XML report file was registered in the database\n";
    exit 0;
} else {
    print LOG "\nRegistered XML report $registeredXMLReportFile.\n";
    $mri_files->{'Preproc'}{'QCReport'}{'xml'}  = $registeredXMLReportFile;
}




    #######################
    ####### Step 5: #######  Register the QC report
    #######################

# $registeredQCReportFile will store the path to the registered QCReportFile
my ($registeredQCReportFile)    = &register_QCReport($QCReport, 
                                                     $dti_file, 
                                                     $data_dir,
                                                     $report_input_fileID,
                                                     $registeredXMLprotocolID,
                                                     "DTIPrepPipeline",
                                                     $DTIPrepVersion);
if (!$registeredQCReportFile) {
    print LOG "\nERROR: no QC report file was registered in the database\n";
    exit 0;
} else {
    print LOG "\nRegistered QC report $registeredQCReportFile.\n";
    $mri_files->{'Preproc'}{'QCReport'}{'txt'}  = $registeredQCReportFile;
}






    #######################
    ####### Step 6: #######  Register DTIPrep preprocessed minc files with associated reports and nrrd files
    #######################

# 6a. Register QCed2 files if defined
if ($mri_files->{'Preproc'}{'QCed2'}{'minc'}) {
    my $QCed2_registered    = &register_Preproc($mri_files,
                                                $dti_file,
                                                $data_dir,
                                                $registeredXMLprotocolID,
                                                "DTIPrepPipeline",
                                                $DTIPrepVersion,
                                                'Preproc', 
                                                'QCed2'
                                                );
    $mri_files->{'Preproc'}{'QCed2'}{'minc'} = $QCed2_registered;
}

# Register QCed files
my $QCed_registered = &register_Preproc($mri_files,
                                        $dti_file,
                                        $data_dir,
                                        $registeredXMLprotocolID,
                                        "DTIPrepPipeline",
                                        $DTIPrepVersion,
                                        'Preproc', 
                                        'QCed'
                                        );
$mri_files->{'Preproc'}{'QCed'}{'minc'} = $QCed_registered;




    #######################
    ####### Step 7: #######  Register post processed files
    #######################

# If mincdiffusion tools were used to create post processed files, register $RGB_minc, $FA_minc, $MD_minc, $baseline_minc, $brain_mask_minc files into the database    
my ($toolName);
if ($mri_files->{'Postproc'}{'Tool'} eq "mincdiffusion") {
    $toolName   = $mincdiffVersion;
} elsif ($mri_files->{'Postproc'}{'Tool'} eq "DTIPrep") {
    $toolName   = $DTIPrepVersion;
}

my ($postproc_registered, 
    $postproc_failed_to_register)   = &register_images($mri_files, 
                                                       $dti_file,
                                                       $data_dir,
                                                       "DTIPrepPipeline",
                                                       $toolName, 
                                                       'Postproc'
                                                      );

# Program is finished
exit 0;









#############
# Functions #
#############

=pod
Register XML protocol file into mri_processing_protocol table.
1. Check if protocol file was already registered in the database. 
2. If protocol file already registered in the database, will return 
the ProcessProtocolID from the database
   If protocol file not registered yet in the database, will register
it in the database and return the ProcessProtocolID of the file 
registered.
Inputs: $XMLProtocol= XML protocol file of DTIPrep to be registered
        $data_dir   = data directory in the prod file
        $tool       = Tool name of the protocol (a.k.a. "DTIPrep")
Outputs:$ProtocolID = ID of the registered protocol file
in mri_processing_protocol table that will be used to register output
files in the files table.
=cut
sub register_XMLProt {
    my ($XMLProtocol, $data_dir, $tool) = @_;
    
    my $md5_check       = `md5sum $XMLProtocol`; 
    my ($md5sum, $file) = split(' ', $md5_check);
    my ($ProtocolID)    = &fetchProtocolID($md5sum);

    return ($ProtocolID)    if ($ProtocolID);

    # Register protocol
    if (!$ProtocolID) {
        ($ProtocolID)   = &registerProtocol($XMLProtocol, $md5sum, $tool, $data_dir);
    }

    return ($ProtocolID); 
}






=pod
Register protocol file into mri_processing_protocol table and move the protocol to the $data_dir/protocols/DTIPrep folder
Inputs: $protocol   = protocol file to be registered
        $md5sum     = md5sum of the protocol file to be registered
        $tool       = tool of the protocol file (DTIPrep)
        $data_dir   = data_dir of the prod file
Output: $protPath if protocol has been successfully moved to the 
datadir/protocol/tool folder and registered into the mri_processing_protocol table.
=cut
sub registerProtocol {
    my ($protocol, $md5sum, $tool, $data_dir) = @_; 

    # Move file into protocol folder
    my $tooldir = $data_dir . "/protocols/" . $tool;
    `mkdir -m 770 $tooldir`    unless (-e $tooldir);
    my $protPath= $tooldir . "/" . basename($protocol);
    `cp $protocol $protPath`    unless (-e $protPath);

    my $query   = "INSERT INTO mri_processing_protocol " .
                  "(ProtocolFile, FileType, Tool, InsertTime, md5sum) " .
                  "VALUES (?, ?, ?, UNIX_TIMESTAMP(), ?)";
    my $sth     = $dbh->prepare($query);

    my $protocolID;
    if (-e $protPath) {
        $sth->execute($protPath, 'xml', $tool, $md5sum);
        $protocolID = &fetchProtocolID($md5sum);
    } else {
        return undef;
    }

    return ($protocolID);
}










=pod
Fetches the protocol ID in the mri_processing_protocol table based on
the XML protocol's md5sum.
Input:  $md5sum     = md5sum of the XML protocol
Output: $ProtocolID = protocol ID from the mri_proceesing_protocol table
of the registered XML protocol file if could find a match with md5sum.
=cut
sub fetchProtocolID {
    my ($md5sum) = @_;

    my $query   = "SELECT ProcessProtocolID " .
                  "FROM mri_processing_protocol " .
                  "WHERE md5sum=?";

    my $sth     = $dbh->prepare($query);
    $sth->execute($md5sum);

    my $protocolID;
    if ($sth->rows > 0) {
        my $row     = $sth->fetchrow_hashref();
        $protocolID = $row->{'ProcessProtocolID'}; 
    }

    return ($protocolID);
}

=pod
Set the different parameters needed for minc files' registration 
and call registerFile to register the minc file in the database
via register_processed_data.pl script. 
Inputs:  - $minc        = minc file to be registered
         - $raw_file    = native file that was the source of the minc file to register
         - $data_dir    = data_dir directory set in the config file (/data/project/data)
         - $inputs      = input files used to obtain minc file to be registered
         - $pipelineName= name of the pipeline used to obtain the minc file (a.k.a. DTIPrepPipeline)
         - $toolName    = tool name and version that was used to obtain the minc file
         - $registeredXMLFile        = registered DTIPrep XML report associated with the minc file
         - $registeredQCReportFile   = registered DTIPrep Txt report associated with the minc file
         - $scanType        = type of scan to be used to register the minc file 
         - $registered_nrrd = optionally, registered nrrd file that was used to create the minc file
Outputs: - $registeredMincFile if minc file was indeed registered in the database
         - undef is not all options could be set or file was not registered in the database
=cut
sub register_minc {
    my ($minc, $raw_file, $data_dir, $inputs, $registeredXMLprotocolID, $pipelineName, $toolName, $registeredXMLFile, $registeredQCReportFile, $scanType, $registered_nrrd)  =   @_;

    print LOG "\n==> File to register is:\n$minc\n";
    print "\n==>File: $minc\n";

    # Determine source file name and source file ID
    my ($src_name)      = basename($raw_file, '.mnc');
    my ($src_fileID)    = &getFileID($minc, $src_name);
    
    # Determine pipeline used to create processed data 
    my  ($src_pipeline, $src_tool, $pipelineName_insert, $toolName_insert);
    if  (!$toolName)    {
        # need to develop this later once DTIPrep versioning will be reported into QC reports.
        ($src_pipeline, $src_tool)  =   &getToolName($minc);
    } else   {
        $src_tool       =   $toolName;
        $src_pipeline   =   $pipelineName;
        # insert pipelineName into the mincheader if not already in.
        ($pipelineName_insert)  = &DTI::modify_header('processing:pipeline', 
                                                      $src_pipeline, 
                                                      $minc,
                                                      '$3, $4, $5, $6');
        ($toolName_insert)      = &DTI::modify_header('processing:tool', 
                                                      $src_tool, 
                                                      $minc,
                                                      '$3, $4, $5, $6');
        return undef    if ((!$toolName_insert) && (!$pipelineName_insert));
    }
    
    # Determine date at which pipeline was run based on registered QC report file
    my  ($pipelineDate) =   &getPipelineDate($minc, $data_dir, $registeredQCReportFile); # if date not in $minc, use QC report and insert it into the mincheader.
    
    # Insert into the mincheader the QC reports (txt & xml)
    my ($Txtreport_insert, 
        $XMLreport_insert)   = &insertReports($minc, 
                                              $registeredXMLFile, 
                                              $registeredQCReportFile
                                             );

    # Insert pipeline summary (how many rejected directions...) into the mincheader
    my ($summary_insert)    = &insertPipelineSummary($minc, 
                                                     $data_dir, 
                                                     $registeredXMLFile, 
                                                     $scanType);

    # Insert into the mincheader processed directory of the minc to register
    my $procdir             = dirname($minc);
    my ($procdir_insert)    = &DTI::modify_header('processing:processed_dir', 
                                                  $procdir,
                                                  $minc,
                                                  '$3, $4, $5, $6');

    # Insert nrrd file into minc file if $registered_nrrd is defined
    my ($nrrd_insert)       = &DTI::modify_header('processing:nrrd_file', $registered_nrrd, $minc, '$3, $4, $5, $6')  if ($registered_nrrd);
    
    # Determine coordinate '}->{'pace
    my ($coordinateSpace);
    $coordinateSpace = "native"      if ($toolName =~ /DTIPrep/i);
    $coordinateSpace = "nativeT1"    if ($toolName =~ /mincdiffusion/i);

    # Determine output type
    my $outputType  =   "qc";

    # Check is all information was correctly inserted into the minc file
    return undef    unless (($Txtreport_insert)     && ($XMLreport_insert) 
                         && ($summary_insert)       && ($toolName_insert)      
                         && ($procdir_insert));
    # Return undef if a nrrd file was registered but not inserted into the mincheader of the associated minc
    return undef    if (($registered_nrrd) && (!$nrrd_insert));

    # If all necessary information are defined, register the file. Return undef otherwise
    if  (($minc)            &&  ($src_fileID)   && 
         ($src_pipeline)    &&  ($pipelineDate) && 
         ($coordinateSpace) &&  ($scanType)     && 
         ($outputType)      &&  ($inputs)       &&
         ($registeredXMLprotocolID)) {

        my  ($registeredMincFile)   = &registerFile($minc, 
                                                    $src_fileID, 
                                                    $src_pipeline, 
                                                    $src_tool,
                                                    $pipelineDate, 
                                                    $coordinateSpace, 
                                                    $scanType, 
                                                    $outputType,
                                                    $inputs,
                                                    $registeredXMLprotocolID
                                                   ); 
        
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
Set parameters needed to register the XML report/protocol of DTIPrep 
and call registerFile to register the XML file via register_processed_data.pl. 
Inputs: - $XMLFile      = XML file to be registered
        - $raw_file     = Native DTI file that was processed to obtain the DTIPrep outputs
        - $data_dir     = data_dir as defined in the config file (a.k.a. /data/project/data)
        - $QCReport     = DTIPrep QCreport 
        - $inputs       = input files that were used to process data through DTIPrep
        - $pipelineName = name of the pipeline used to process DTIs (DTIPrepPipeline)
        - $toolName     = DTIPrep name and version that was used to process DTIs
Outputs: - $registeredXMLFile if the XML file was indeed registered in the database
         - undef if could not set all parameters for registration or file could not be registered in the database
=cut
sub register_XMLFile {
    my ($XMLFile, $raw_file, $data_dir, $QCReport, $inputs, $registeredXMLprotocolID, $pipelineName, $toolName) =   @_;

    print LOG "\n==> File to register is:\n$XMLFile\n";
    print "\n==>File: $XMLFile\n";

    my  $src_name   = basename($raw_file, '.mnc');
    my  $src_fileID = &getFileID($XMLFile, $src_name);

    my  ($src_pipeline, $src_tool);
    if  (!$toolName)    {
        print "WARNING: This should not happen as long as the pipeline versioning of DTIPrep is not fixed!"; 
        exit 33; 
        # Will need to program this part once DTIPrep fixed!
        #($src_pipeline, $src_tool)=getToolName($XMLFile);
    }else   {
        $src_pipeline   =   $pipelineName;
        $src_tool       =   $toolName;
    }

    my ($pipelineDate)  =   &getPipelineDate($XMLFile, $data_dir, $QCReport);

    my $coordinateSpace =   "native";
    my ($scanType, $outputType);
    if ($XMLFile =~ /XMLQCResult\.xml$/i) {
        $scanType       =   "DTIPrepXMLQCReport";
        $outputType     =   "qcreport";
    } elsif ($XMLFile =~ /DTIPrepProtocol\.xml$/i) {
        $scanType       =   "DTIPrepXMLProtocol";
        $outputType     =   "protocol";
    }
    # register file if all information are available
    if  (($XMLFile)         &&  ($src_fileID)   &&
         ($src_pipeline)    &&  ($pipelineDate) &&
         ($coordinateSpace) &&  ($scanType)     &&
         ($outputType)      &&  ($inputs)       &&
         ($registeredXMLprotocolID)) {

        my  ($registeredXMLFile)  = &registerFile($XMLFile,
                                                  $src_fileID,
                                                  $src_pipeline,
                                                  $src_tool,
                                                  $pipelineDate,
                                                  $coordinateSpace,
                                                  $scanType,
                                                  $outputType,
                                                  $inputs,
                                                  $registeredXMLprotocolID
                                                 );

        return ($registeredXMLFile);

    } else {

        print LOG "\nERROR: a required option for register_processed_data.pl is not set!!\n";
        print LOG "sourceFileID:    $src_fileID\n"      .
                  "sourcePipeline:  $src_pipeline\n"    .
                  "pipelineDate:    $pipelineDate\n"    .
                  "coordinateSpace: $coordinateSpace\n" .
                  "scanType:        $scanType\n"        .
                  "outputType:      $outputType\n"      .
                  "protocolID:      $registeredXMLprotocolID\n";
        return undef;

    }
}        

=pod
Set parameters needed to register the QCreport of DTIPrep 
and call registerFile to register the QCreport file via register_processed_data.pl. 
Inputs: - $QCReport     = QC report file to be registered
        - $raw_file     = Native DTI file that was processed to obtain the DTIPrep outputs
        - $data_dir     = data_dir as defined in the config file (a.k.a. /data/project/data)
        - $inputs       = input files that were used to process data through DTIPrep
        - $pipelineName = name of the pipeline used to process DTIs (DTIPrepPipeline)
        - $toolName     = DTIPrep name and version that was used to process DTIs
Outputs: - $registeredQCReportFile if the QC report file was indeed registered in the database
         - undef if could not set all parameters for registration or file could not be registered in the database
=cut
sub register_QCReport {
    my ($QCReport, $raw_file, $data_dir, $inputs, $registeredXMLprotocolID, $pipelineName, $toolName)    =   @_;

    print LOG "\n==> File to register is:\n$QCReport\n";
    print "\n==>File: $QCReport\n";

    my  $src_name   = basename($raw_file, '.mnc');
    my  $src_fileID = &getFileID($QCReport,$src_name);

    my  ($src_pipeline, $src_tool);
    if  (!$toolName)    {
        print "WARNING: This should not happen as long as the pipeline versioning of DTIPrep is not fixed!"; 
        exit 33; 
        # Will need to program this part once DTIPrep fixed!
        #($src_pipeline, $src_tool)=getToolName($QCReport);
    }else   {
        $src_pipeline =   $pipelineName;
        $src_tool     =   $toolName;
    }

    my ($pipelineDate)  =   &getPipelineDate($QCReport, $data_dir, $QCReport);

    my $coordinateSpace =   "native";
    my $scanType        =   "DTIPrepQCReport";
    my $outputType      =   "qcreport";

    if  (($QCReport)        &&  ($src_fileID)   &&
         ($src_pipeline)    &&  ($pipelineDate) &&
         ($coordinateSpace) &&  ($scanType)     &&
         ($outputType)      &&  ($inputs)       &&
         ($registeredXMLprotocolID)) {

        my  ($registeredQCReportFile) = &registerFile($QCReport,
                                                      $src_fileID,
                                                      $src_pipeline,
                                                      $src_tool,
                                                      $pipelineDate,
                                                      $coordinateSpace,
                                                      $scanType,
                                                      $outputType,
                                                      $inputs,
                                                      $registeredXMLprotocolID
                                                     );

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
    my  $XMLProtocol=   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCProt'}->{'xml'};
    my  $QCReport   =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCReport'}->{'txt'};
    my  $XMLReport  =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCReport'}->{'xml'};
    my  $QCed_nrrd  =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed'}{'nrrd'};
    my  $QCed_minc  =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed'}{'minc'};
    my  $QCed2_nrrd =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed2'}{'nrrd'};
    my  $QCed2_minc =   $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed2'}{'minc'};

    # Check that all outputs exist in the filesystem and return them (except the nrrd ones).
    if ((-e $XMLProtocol) && (-e $QCReport) && (-e $XMLReport) && (-e $QCed_nrrd) && (-e $QCed_minc)) {

        $mri_files->{'Preproc'}{'QCed'}{'nrrd'}      = $QCed_nrrd;
        $mri_files->{'Preproc'}{'QCed'}{'minc'}      = $QCed_minc;
        $mri_files->{'Preproc'}{'QCed'}{'scanType'}  = 'DTIPrepReg';
        $mri_files->{'Preproc'}{'QCed2'}{'nrrd'}     = $QCed2_nrrd;
        $mri_files->{'Preproc'}{'QCed2'}{'minc'}     = $QCed2_minc;
        $mri_files->{'Preproc'}{'QCed2'}{'scanType'} = 'DTIPrepNoReg';
        $mri_files->{'Preproc'}{'QCed'}{'inputs'}    = $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed'}->{'inputs'};   
        $mri_files->{'Preproc'}{'QCed2'}{'inputs'}   = $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed2'}->{'inputs'};   
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
    my  $RGB_minc       =   $DTIrefs->{$dti_file}->{'Postproc'}->{'RGB'}->{'minc'}; 
    my  $FA_minc        =   $DTIrefs->{$dti_file}->{'Postproc'}->{'FA'}->{'minc'};
    my  $MD_minc        =   $DTIrefs->{$dti_file}->{'Postproc'}->{'MD'}->{'minc'};
    my  $baseline_minc  =   $DTIrefs->{$dti_file}->{'Postproc'}->{'baseline'}->{'minc'};

    if ((-e $RGB_minc) && (-e $FA_minc) && (-e $MD_minc) && (-e $baseline_minc)) {
        $mri_files->{'Postproc'}{'RGB'}{'minc'}         = $RGB_minc;
        $mri_files->{'Postproc'}{'RGB'}{'scanType'}     = 'DTIPrepDTIColorFA';
        $mri_files->{'Postproc'}{'FA'}{'minc'}          = $FA_minc;
        $mri_files->{'Postproc'}{'FA'}{'scanType'}      = 'DTIPrepDTIFA';
        $mri_files->{'Postproc'}{'MD'}{'minc'}          = $MD_minc;
        $mri_files->{'Postproc'}{'MD'}{'scanType'}      = 'DTIPrepDTIMD';
        $mri_files->{'Postproc'}{'baseline'}{'minc'}    = $baseline_minc;
        $mri_files->{'Postproc'}{'baseline'}{'scanType'}= 'DTIPrepBaseline';
    } else {
        print LOG "Could not find postprocessing minc files on the filesystem.\n";
        return undef;
    }

    # Check which tool has been used to post process DTI dataset to validate that all outputs are found in the filsystem
    my  ($RGB_nrrd, $FA_nrrd, $MD_nrrd, $baseline_nrrd, $brain_mask_minc, $IDWI_nrrd, $tensor_nrrd);
    if ($DTIrefs->{$dti_file}->{'Postproc'}->{'Tool'} eq "DTIPrep") {

        # Store tool used for Postprocessing in %mri_files
        $mri_files->{'Postproc'}{'Tool'}    = "DTIPrep";

        # File specific to DTIPrep post-processing
        my  $IDWI_minc      =   $DTIrefs->{$dti_file}->{'Postproc'}->{'IDWI'}->{'minc'};
        my  $tensor_minc    =   $DTIrefs->{$dti_file}->{'Postproc'}->{'tensor'}->{'minc'};
        if ((-e $IDWI_minc) && (-e $tensor_minc)) {
            $mri_files->{'Postproc'}{'IDWI'}{'minc'}        = $IDWI_minc; 
            $mri_files->{'Postproc'}{'IDWI'}{'scanType'}    = 'DTPrepIDWI'; 
            $mri_files->{'Postproc'}{'tensor'}{'minc'}      = $tensor_minc; 
            $mri_files->{'Postproc'}{'tensor'}{'scanType'}  = 'DTIPrepDTI'; 
        } else {
            print LOG "Could not find post processing isotropic minc files on the filesystem.\n";
            return undef;
        }

        # Fetches info about DTIPrep nrrd post processing files
        $RGB_nrrd       =   $DTIrefs->{$dti_file}->{'Postproc'}->{'RGB'}->{'nrrd'}; 
        $FA_nrrd        =   $DTIrefs->{$dti_file}->{'Postproc'}->{'FA'}->{'nrrd'};
        $MD_nrrd        =   $DTIrefs->{$dti_file}->{'Postproc'}->{'MD'}->{'nrrd'};
        $baseline_nrrd  =   $DTIrefs->{$dti_file}->{'Postproc'}->{'baseline'}->{'nrrd'};
        $IDWI_nrrd      =   $DTIrefs->{$dti_file}->{'Postproc'}->{'IDWI'}->{'nrrd'};
        $tensor_nrrd    =   $DTIrefs->{$dti_file}->{'Postproc'}->{'tensor'}->{'nrrd'};

        # Return minc files if all nrrd and minc outputs exist on the filesystem
        if ((-e $RGB_nrrd) && (-e $FA_nrrd) && (-e $MD_nrrd) && (-e $baseline_nrrd) && (-e $IDWI_nrrd) && (-e $tensor_nrrd)) {
            $mri_files->{'Postproc'}{'RGB'}{'nrrd'}         = $RGB_nrrd;
            $mri_files->{'Postproc'}{'FA'}{'nrrd'}          = $FA_nrrd;
            $mri_files->{'Postproc'}{'MD'}{'nrrd'}          = $MD_nrrd;
            $mri_files->{'Postproc'}{'baseline'}{'nrrd'}    = $baseline_nrrd;
            $mri_files->{'Postproc'}{'IDWI'}{'nrrd'}        = $IDWI_nrrd;
            $mri_files->{'Postproc'}{'tensor'}{'nrrd'}      = $tensor_nrrd;
            foreach my $proc (keys ($mri_files->{'Postproc'})) {
                next if ($proc eq "Tool");
                $mri_files->{'Postproc'}{$proc}{'inputs'}   = $DTIrefs->{$dti_file}{'Postproc'}{$proc}{'inputs'};
            }

            return 1;
        } else {
            print LOG "Could not find all DTIPrep postprocessing outputs on the filesystem.\n";
            return undef;
        }

    } elsif ($DTIrefs->{$dti_file}->{'Postproc'}->{'Tool'} eq "mincdiffusion") {

        # Store tool used for Postprocessing in %mri_files
        $mri_files->{'Postproc'}{'Tool'}    = "mincdiffusion";

        # Extract brain mask used by the diffusion tools
        $brain_mask_minc=   $DTIrefs->{$dti_file}->{'Postproc'}->{'anat_mask_diff'}->{'minc'};
        # Return minc files if all minc outputs exist on the filesystem
        if (-e $brain_mask_minc) {
            $mri_files->{'Postproc'}{'anat_mask_diff'}{'minc'}    = $brain_mask_minc;
            $mri_files->{'Postproc'}{'anat_mask_diff'}{'scanType'}= 'DTIPrepBetMask';
            foreach my $proc (keys ($mri_files->{'Postproc'})) {
                next if ($proc eq "Tool");
                $mri_files->{'Postproc'}{$proc}{'inputs'}   = $DTIrefs->{$dti_file}{'Postproc'}{$proc}{'inputs'};
            }
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
Fetches the source FileID from the database based on the src_name file identified by getFileName.
Inputs: - $file     = output filename 
        - $src_name = source filename (file that has been used to obtain $file)
Outputs: - $fileID  = source File ID (file ID of the source file that has been used to obtain $file)
=cut
sub getFileID {
    my  ($file, $src_name) = @_;

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
        print LOG "WARNING: No fileID matches the dataset $src_name used to produce $file.\n\n\n";
    }
    
    return  ($fileID);
}





=pod
Fetches tool informations stored either in the minc's header or in the QCReport.
Inputs:  - $file        = minc or QC report to look for tool information
Outputs: - $src_pipeline= name of the pipeline used to obtain $file (a.k.a. DTIPrepPipeline)
         - $src_tool    = name and version of the tool used to obtain $file (DTIPrep_v1.1.6, mincdiffusion_v...)
=cut
sub getToolName {    
    my  ($file)     =   @_;

    my  $src_pipeline   = &DTI::fetch_header_info('processing:pipeline',
                                                  $file,
                                                  '$3');
    my  $src_tool       = &DTI::fetch_header_info('processing:tool',
                                                  $file,
                                                  '$3');
    if  ((!$src_tool) && (!$src_pipeline))  {
        print LOG "ERROR: no tool have been found in mincheader of $file. Check that the processing:pipeline field exits or specify which tool was used manually with the option -DTIPrepVersion or -mincdiffusionVersion as input of the script DTIPrepRegister.pl."; 
        exit 33;
    }else   {
        #remove leading spaces, trailing spaces and all instances of "
        $src_tool       =~s/"//g;
        $src_pipeline   =~s/"//g;
    }
    
    return  ($src_pipeline, $src_tool);
}

=pod
Fetches the date at which DTIPrep pipeline was run either in the processed minc's header or in the QCReport.
Inputs:  - $file            = minc or QC report to look for tool information
         - $data_dir        = data_dir stored in the config file
         - $QCReport        = QC report created when $file was created
Outputs: - $pipeline_date   = date at which the pipeline has been run to obtain $file
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
    
        print LOG "\n> Fetching date of processing in the QCReport.txt file created by DTIPrep\n";
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
Insert in mincheader the path to DTIPrep's QC txt and xml reports and xml protocol.
Inputs:  - $minc                     = minc file to modify header
         - $registeredXMLFile        = path to the registered DTIPrep's XML report
         - $registeredQCReportFile   = path to the registered DTIPrep's QC txt report
Outputs: - $Txtreport_insert    = 1 if text report path insertion was successful
                                = undef if text report path was not inserted
         - $XMLreport_insert    = 1 if xml report path insertion was successful
                                = undef if xml report path was not inserted
         - $protocol_insert     = 1 if xml protocol path insertion was successful
                                = undef if xml protocol path was not inserted
=cut
sub insertReports {
    my ($minc, $registeredXMLFile, $registeredQCReportFile) = @_;

    # Return undef if there is at least one missing function argument
    return undef    unless (($minc) && ($registeredXMLFile) && ($registeredQCReportFile));

    # Insert files into the mincheader
    my ($Txtreport_insert)  = &DTI::modify_header('processing:DTIPrepTxtReport',
                                                  $registeredQCReportFile,     
                                                  $minc,
                                                  '$3, $4, $5, $6');
    my ($XMLreport_insert)  = &DTI::modify_header('processing:DTIPrepXmlReport',
                                                  $registeredXMLFile, 
                                                  $minc,
                                                  '$3, $4, $5, $6');

    return ($Txtreport_insert, $XMLreport_insert);
}






=pod
Insert in mincheader a summary of DTIPrep reports.
This summary consist of the directions rejected due to slice wise correlation,
the directions rejected due to interlace correlation,
and the directions rejected due to gradient wise correlation
Inputs:  - $minc     = minc file in which the summary will be inserted
         - $data_dir = data_dir as defined in the config file
         - $QCReport = DTIPrep's QC report from which the summary will be extractec
Outputs: - 1 if all information has been successfully inserted
         - undef if at least one information has not been inserted
=cut
sub insertPipelineSummary   {
    my ($minc, $data_dir, $XMLReport, $scanType)   =   @_;

    my ($summary)   =   &DTI::getRejectedDirections($data_dir, $XMLReport);
    
    # insert slice wise excluded gradients in mincheader
    my $rm_slicewise        = $summary->{'EXCLUDED'}{'slice'}{'txt'};
    my $count_slice         = $summary->{'EXCLUDED'}{'slice'}{'nb'};
    my ($insert_slice)      = &DTI::modify_header('processing:slicewise_rejected',
                                                  $rm_slicewise,
                                                  $minc,
                                                  '$3, $4, $5, $6');

    # insert interlace wise excluded gradients in mincheader
    my $rm_interlace        = $summary->{'EXCLUDED'}{'interlace'}{'txt'};
    my $count_interlace     = $summary->{'EXCLUDED'}{'interlace'}{'nb'};
    my ($insert_inter)      = &DTI::modify_header('processing:interlace_rejected',
                                                  $rm_interlace,
                                                  $minc, 
                                                  '$3, $4, $5, $6');

    # insert total count (and intergradient count except if scanType is DTIPrepNoReg
    my $count_intergradient = $summary->{'EXCLUDED'}{'intergrad'}{'nb'};
    my $count_total         = $summary->{'EXCLUDED'}{'total'}{'nb'};
    my ($rm_intergradient, $insert_gradient, $total);
    if ($scanType =~ /DTIPrepNoReg/i) {
        # compute total number of excluded gradients and insert it in mincheader
        $total  = $count_total - $count_intergradient;
    } else {
        # insert intergradient wise excluded gradients in mincheader
        $rm_intergradient   = $summary->{'EXCLUDED'}{'intergrad'}{'txt'};
        ($insert_gradient)  = &DTI::modify_header('processing:intergradient_rejected',
                                                  $rm_intergradient,
                                                  $minc,
                                                  '$3, $4, $5, $6');
        # total is equal to count_total
        $total  = $count_total;
    }
    # compute total number of excluded gradients and insert it in mincheader
    my ($total_insert)     = &DTI::modify_header('processing:total_rejected', 
                                                 $total, 
                                                 $minc,
                                                 '$3, $4, $5, $6');

    # If all insertions went well, return 1, otherwise return undef
    if (($total_insert) && ($insert_slice) && ($insert_inter) 
            && (($insert_gradient) || ($scanType =~ /DTIPrepNoReg/i))) {
        return 1;
    } else {
        return undef;
    }
}






=pod
Register file into the database via register_processed_data.pl with all options.
Inputs:  - $file            = file to be registered in the database
         - $src_fileID      = FileID of the source file used to obtain the file to be registered
         - $src_pipeline    = Pipeline used to obtain the file (DTIPrepPipeline)
         - $src_tool        = Name and version of the tool used to obtain the file (DTIPrep or mincdiffusion)
         - $pipelineDate    = file's creation date (= pipeline date)
         - $coordinateSpace = file's coordinate space (= native, T1 ...)
         - $scanType        = file's scan type (= DTIPrepReg, DTIPrepDTIFA, DTIPrepDTIMD, DTIPrepDTIColorFA...)
         - $outputType      = file's output type (.xml, .txt, .mnc...)
         - $inputs          = files that were used to create the file to be registered (intermediary files)
Outputs: - $registeredFile  = file that has been registered in the database
=cut
sub registerFile  {
    my  ($file, $src_fileID, $src_pipeline, $src_tool, $pipelineDate, $coordinateSpace, $scanType, $outputType, $inputs, $registeredXMLprotocolID)    =   @_;

    # Check if File has already been registered into the database. Return File registered if that is the case.
    my ($alreadyRegistered) = &fetchRegisteredFile($src_fileID, $src_pipeline, $pipelineDate, $coordinateSpace, $scanType, $outputType);
    if ($alreadyRegistered) {
        print LOG "> File $file already registered into the database.\n";
        return ($alreadyRegistered);
    }

    # Print LOG information about the file to be registered
    print LOG "\n\t- sourceFileID is: $src_fileID\n";
    print LOG "\t- src_pipeline is: $src_pipeline\n";
    print LOG "\t- tool is: $src_tool\n";
    print LOG "\t- pipelineDate is: $pipelineDate\n";
    print LOG "\t- coordinateSpace is: $coordinateSpace\n";
    print LOG "\t- scanType is: $scanType\n";
    print LOG "\t- outputType is: $outputType\n";
    print LOG "\t- inputFileIDs is: $inputs\n";

    # Register the file into the database using command $cmd
    my $cmd =   "register_processed_data.pl " .
                    "-profile $profile " .
                    "-file $file " .
                    "-sourceFileID $src_fileID " .
                    "-sourcePipeline $src_pipeline " .
                    "-tool $src_tool " .
                    "-pipelineDate $pipelineDate " .
                    "-coordinateSpace $coordinateSpace " .
                    "-scanType $scanType " .
                    "-outputType $outputType  " .
                    "-inputFileIDs \"$inputs\" " .
                    "-protocolID $registeredXMLprotocolID";
    system($cmd);
    print LOG "\n==> Command sent:\n$cmd\n";
    
    my  ($registeredFile) = &fetchRegisteredFile($src_fileID, $src_pipeline, $pipelineDate, $coordinateSpace, $scanType, $outputType);

    if (!$registeredFile) {
        print LOG "> WARNING: No fileID found for SourceFileID=$src_fileID, SourcePipeline=$src_pipeline, PipelineDate=$pipelineDate, CoordinateSpace=$coordinateSpace, ScanType=$scanType and OutputType=$outputType.\n\n\n";
    }    

    return ($registeredFile);
}        





=pod
Fetch the registered file from the database to link it to the minc files.
Inputs:  - $src_fileID      = FileID of the native file used to register the processed file
         - $src_pipeline    = Pipeline name used to register the processed file
         - $pipelineDate    = Pipeline data used to register the processed file
         - $coordinateSpace = coordinate space used to register the processed file
         - $scanType        = scan type used to register the processed file
         - $outputType      = output type used to register the processed file
Outputs: - $registeredFile  = path to the registered processed file
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
    }

    return  ($registeredFile);

}







=pod
Register DTIPrep nrrd and minc files. The minc file will have a link to the registered nrrd file (register_minc function will modify mincheader to include this information) in addition to the links toward QC reports and protocol.
- Inputs:   - files to be registered ($minc, $nrrd)
            - registered QC report files ($registeredXMLReportFile, $registeredQCReportFile)
            - $DTIPrepVersion used to produce the files
- Outputs:  - registered minc files if the nrrd and minc files were successfully registered in the database
            - undef if one argument of the function if missing or if nrrd file could not be registered
=cut
sub register_DTIPrep_files {
    my  ($minc, $nrrd, $raw_file, $data_dir, $inputs, $registeredXMLprotocolID, $pipelineName, $DTIPrepVersion, $registeredXMLReportFile, $registeredQCReportFile, $scanType) = @_;

    # Return undef if variables given as arguments are not defined
    return undef    unless (($minc)                    && ($nrrd)                  
                         && ($DTIPrepVersion)          && ($registeredXMLReportFile) 
                         && ($registeredQCReportFile)  && ($registeredXMLprotocolID)
                         && ($pipelineName)            && ($inputs));

    # Register nrrd file into the database
    # First checks if DTIPrepReg file exists in DB (could be identical to $noRegQCedDTI)
    my ($registeredFile, $registeredScanType, $registered_nrrd);
    if ($scanType eq "DTIPrepReg") {
        my $md5_check       = `md5sum $nrrd`; 
        my ($md5sum, $file) = split(' ', $md5_check);
        ($registeredFile, 
        $registeredScanType)= &fetchRegisteredMD5($md5sum);
        $registered_nrrd    = $registeredFile if ($registeredScanType eq 'DTIPrepNoReg');
    }
    # Register nrrd file unless already registered
    unless ($registered_nrrd) {
        ($registered_nrrd)  = &register_nrrd($nrrd,
                                             $raw_file,
                                             $data_dir,
                                             $registeredQCReportFile,
                                             $inputs,
                                             $registeredXMLprotocolID,
                                             $pipelineName,
                                             $DTIPrepVersion,
                                             $scanType
                                            );
    }
    return undef    if (!$registered_nrrd);

    # Register minc file into the database with link to the QC reports, protocol and registered nrrd
    my ($registered_minc)   = &register_minc($minc,
                                             $raw_file,
                                             $data_dir,
                                             $inputs,
                                             $registeredXMLprotocolID,
                                             $pipelineName,
                                             $DTIPrepVersion,
                                             $registeredXMLReportFile,
                                             $registeredQCReportFile,
                                             $scanType,
                                             $registered_nrrd
                                            );

    # Return registered minc file
    return ($registered_minc);
}






=pod
Set parameters needed to register the nrrd file produced by DTIPrep 
and call registerFile to register the nrrd file via register_processed_data.pl. 
Inputs: - $nrrd         = nrrd file to be registered
        - $raw_file     = Native DTI file that was processed to obtain the DTIPrep outputs
        - $data_dir     = data_dir as defined in the config file (a.k.a. /data/project/data)
        - $QCReport     = DTIPrep QCreport 
        - $inputs       = input files that were used to process data through DTIPrep
        - $pipelineName = name of the pipeline used to process DTIs (DTIPrepPipeline)
        - $toolName     = DTIPrep name and version that was used to process DTIs
        - $scanType     = nrrd file's scan type
Outputs: - $registeredNrrdFile if the nrrd file was indeed registered in the database
         - undef if could not set all parameters for registration or file could not be registered in the database
=cut
sub register_nrrd {
    my ($nrrd, $raw_file, $data_dir, $QCReport, $inputs, $registeredXMLprotocolID, $pipelineName, $toolName, $scanType) =   @_;

    print LOG "\n==> File to register is:\n$nrrd\n";
    print "\n==>File: $nrrd\n";

    my  $src_name   = basename($raw_file, '.mnc');
    my  $src_fileID = &getFileID($nrrd, $src_name);

    my  ($src_pipeline, $src_tool);
    if  (!$toolName)    {
        print "WARNING: This should not happen as long as the pipeline versioning of DTIPrep is not fixed!";
        exit 33;
        # Will need to program this part once DTIPrep fixed!
        #($src_pipeline, $src_tool)=getToolName($XMLFile);
    }else   {
        $src_pipeline   =   $pipelineName;
        $src_tool       =   $toolName;
    }

    my ($pipelineDate)  =   &getPipelineDate($nrrd, $data_dir, $QCReport);

    my ($coordinateSpace);
    $coordinateSpace = "native"      if ($toolName =~ /DTIPrep/i);
    $coordinateSpace = "nativeT1"    if ($toolName =~ /mincdiffusion/i);

    my $outputType      =   "qcnrrd";

    # register file if all information are available
    if  (($nrrd)            &&  ($src_fileID)   &&
         ($src_pipeline)    &&  ($pipelineDate) &&
         ($coordinateSpace) &&  ($scanType)     &&
         ($outputType)      &&  ($inputs)       &&
         ($registeredXMLprotocolID)) {

        my  ($registeredNrrdFile)  = &registerFile($nrrd,
                                                   $src_fileID,
                                                   $src_pipeline,
                                                   $src_tool,
                                                   $pipelineDate,
                                                   $coordinateSpace,
                                                   $scanType,
                                                   $outputType,
                                                   $inputs,
                                                   $registeredXMLprotocolID
                                                  );

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





=pod
Gather all DTIPrep preprocessed files to be registered in the database
and call register_DTIPrep_files on all of them. Will register first the 
nrrd file and then the minc file for each scan type.
Inputs:  - $mri_files       = hash containing all DTI output information
         - $dti_file        = native DTI file that was processed (that will be used as a key for $mri_files)
         - $data_dir        = data_dir defined in the config file
         - $pipelineName    = name of the pipeline used to preprocess data (DTIPrepPipeline)
         - $toolName        = name and version of the tool used to preprocess data
         - $process_step    = processing step ('Preproc' or 'Postproc') depending on the processed file
         - $proc_file       = key to the processed file to be registered ('QCed', 'QCed2'...)
Outputs: - $registered_minc = path to the minc file that was registered
=cut
sub register_Preproc {
    my ($mri_files, $dti_file, $data_dir, $registeredXMLprotocolID, $pipelineName, $toolName, $process_step, $proc_file) = @_;

    # Get the registered reports and protocol
    my $registeredXMLReportFile     = $mri_files->{'Preproc'}{'QCReport'}{'xml'};
    my $registeredQCReportFile      = $mri_files->{'Preproc'}{'QCReport'}{'txt'};

    # register file into the database
    my $minc        = $mri_files->{$process_step}{$proc_file}{'minc'};
    my $scanType    = $mri_files->{$process_step}{$proc_file}{'scanType'};
    my ($inputs)    = &getInputList($mri_files, $data_dir, $process_step, $proc_file);
    my $nrrd        = $mri_files->{$process_step}{$proc_file}{'nrrd'};

    # register DTIPrep files
    my ($registered_minc)   = &register_DTIPrep_files($minc,
                                                      $nrrd,
                                                      $dti_file,
                                                      $data_dir,
                                                      $inputs,
                                                      $registeredXMLprotocolID,
                                                      $pipelineName,
                                                      $toolName,
                                                      $registeredXMLReportFile,
                                                      $registeredQCReportFile,
                                                      $scanType
                                                     );

    return ($registered_minc);
}






=pod
Function to register processed images in the database depending on the tool used to obtain them. 
Will call register_DTIPrep_files if files to be registered are obtained via DTIPrep
or register_minc if files to be registered are obtained using mincdiffusion tools.
Inputs:  - $mri_files: hash containing information about the files to be registered
         - $raw_file: source raw image used to obtain processed files to be registered
         - $data_dir: data directory where all images are stored (set in the prod file)
         - $pipelineName: name of the pipeline used (a.k.a DTIPrep)
         - $toolName: version and name of the tool used to produce the images to be registered
         - $process_step: processing step (preprocessing, post-processing)
Outputs: - @registered: list of registered files
         - @failed_to_register: list of files that failed to be registered in the database
=cut
sub register_images {
    my ($mri_files, $raw_file, $data_dir, $pipelineName, $toolName, $process_step) = @_;

    # Get the registered reports and protocol
    my $registeredXMLReportFile     = $mri_files->{'Preproc'}{'QCReport'}{'xml'};
    my $registeredQCReportFile      = $mri_files->{'Preproc'}{'QCReport'}{'txt'};
    my $registeredXMLprotocolID     = $mri_files->{'Preproc'}{'QCProt'}{'xml'};

    my (@registered, @failed_to_register, $registered_minc);
    foreach my $proc_file (keys($mri_files->{$process_step})) {

        # Don't register key that is Tool (stores tool used for processing)
        next    if ($proc_file eq "Tool");

        # register file into the database
        my $minc        = $mri_files->{$process_step}{$proc_file}{'minc'};
        my $scanType    = $mri_files->{$process_step}{$proc_file}{'scanType'};
        my ($inputs)    = &getInputList($mri_files, $data_dir, $process_step, $proc_file);

        if ($mri_files->{$process_step}{'Tool'} eq "DTIPrep") {

            my $nrrd    = $mri_files->{$process_step}{$proc_file}{'nrrd'};
            ($registered_minc)   = &register_DTIPrep_files($minc,
                                                           $nrrd,
                                                           $raw_file,
                                                           $data_dir,
                                                           $inputs,
                                                           $registeredXMLprotocolID,
                                                           $pipelineName,
                                                           $toolName, 
                                                           $registeredXMLReportFile, 
                                                           $registeredQCReportFile, 
                                                           $scanType
                                                          );

        } elsif ($mri_files->{$process_step}{'Tool'} eq "mincdiffusion") {

            ($registered_minc)   = &register_minc($minc,
                                                  $raw_file,
                                                  $data_dir,
                                                  $inputs,
                                                  $registeredXMLprotocolID,
                                                  $pipelineName,
                                                  $toolName,
                                                  $registeredXMLReportFile,
                                                  $registeredQCReportFile,
                                                  $scanType
                                                 );

        }
        
        # Update the minc file in mri_files to the registered_minc;
        $mri_files->{$process_step}{$proc_file}{'minc'} = $registered_minc;

        # push into array registered the registered file
        push(@registered, $registered_minc) if ($registered_minc);
        push(@failed_to_register, $minc)    if (!$registered_minc);
    }
    
    return (\@registered, \@failed_to_register);
}



=pod
Function that will return in a string the list of inputs used to process the data separated by ';'.
Inputs: - $mri_files    = list of processed outputs to registered or that have been registered
        - $process_step = processing step used for the processed output to determine inputs
        - $proc_file    = processing file to determine inputs used 
Outputs:- $inputs_list  = string with each inputs used separated by ';'
=cut
sub getInputList {
    my ($mri_files, $data_dir, $process_step, $proc_file) = @_;

    my @inputs; 
    foreach my $input (keys $mri_files->{$process_step}{$proc_file}{'inputs'}) {
        my $input_file;
        if ($input =~ m/Raw/i) {
            $input_file = $mri_files->{$process_step}{$proc_file}{'inputs'}{$input};
            $input_file =~ s/$data_dir\///;
        } elsif (($input =~ m/QCed/i)) {
            $input_file = $mri_files->{'Preproc'}{$input}{'minc'};
        } else {
            return undef;
        }
        my $input_fileID= &getFileID($proc_file, $input_file);
        return undef    if (!$input_fileID);
        push (@inputs, $input_fileID);
    }

    # If inputs has only one entry, input_list=inputs[0], if more than one entry, list all entries separated by ;. Return undef if no entry stored in inputs
    my $input_list;
    if ($#inputs == 0) {
        $input_list = $inputs[0];
    } elsif ($#inputs > 0) {
        $input_list = join(';', @inputs);
    } else {
        return undef;
    }

    return ($input_list);
}    







=pod
Will check if md5sum has already been registered into the database.
Input:  - $md5sum: md5sum of the file
Output: - $registeredFileID: registered FileID matching md5sum
        - $registeredScanType: scan type of the registered FileID matching md5sum
=cut
sub fetchRegisteredMD5 {
    my ($md5sum) = @_;

    my $query   = "SELECT File, Scan_type" .
                    " FROM files f" .
                    " JOIN parameter_file pf ON (pf.FileID = f.FileID)" .
                    " JOIN parameter_type pt ON (pt.ParameterTypeID = pf.ParameterTypeID)" .
                    " JOIN mri_scan_type mst ON (mst.ID=f.AcquisitionProtocolID)" .
                    " WHERE pt.Name = ? AND pf.Value = ?";
    my $sth     = $dbh->prepare($query);
    $sth->execute('md5hash', $md5sum);
    my ($registeredFile, $registeredScanType);
    if  ($sth->rows > 0)    {
        my $row =   $sth->fetchrow_hashref();
        $registeredFile   = $row->{'File'};
        $registeredScanType = $row->{'Scan_type'}
    }

    return ($registeredFile, $registeredScanType);
}

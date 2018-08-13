#!/usr/bin/perl -w

=pod

=head1 NAME

DTIPrepRegister.pl -- registers C<DTIPrep> outputs in the LORIS database

=head1 SYNOPSIS

perl DTIPrepRegister.pl C<[options]>

Available options are:

-profile        : name of the config file in C<../dicom-archive/.loris-mri>

-DTIPrep_subdir : C<DTIPrep> subdirectory storing the processed files to
                   be registered

-DTIPrepProtocol: C<DTIPrep> protocol used to obtain the output files

-DTI_file       : native DWI file used to obtain the output files

-anat_file      : native anatomical dataset used to create FA, RGB and
                   other post-processed maps using C<mincdiffusion> tools

-DTIPrepVersion : C<DTIPrep> version used if it cannot be found in MINC
                   files' C<processing:pipeline> header field

-mincdiffusionVersion: C<mincdiffusion> release version used if it cannot be
                        found in minc files' C<processing:pipeline>
                        header field

Note: C<-DTIPrepVersion> and C<-mincdiffusionVersion> are optional if the
version of those tools can be found directly in the MINC header of the
processed files.

=head1 DESCRIPTION

Registers DWI QC pipeline's output files of interest into the LORIS database
via C<register_processed_data.pl>.

The following output files will be inserted:
  - QCed MINC file produced by C<DTIPrep> pre-processing step (i.e. DWI
     dataset without the bad directions detected by C<DTIPrep>)
  - Text QC report produced by DTPrep
  - XML QC report produced by C<DTIPrep>
  - RGB map produced by either C<DTIPrep> or C<mincdiffusion> post-processing
  - MD map produced by either C<DTIPrep> or C<mincdiffusion> post-processing
  - FA map produced by either C<DTIPrep> or C<mincdiffusion> post-processing
  - baseline image produced by C<DTIPrep> or C<mincdiffusion> post-processing
  - DTI mask produced by C<mincdiffusion> post-processing (only if
     C<mincdiffusion> was used to post-process the data)

=head2 Methods

=cut


use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use FindBin;
use Date::Parse;
use XML::Simple;
use lib "$FindBin::Bin";

# These are to load the DTI & DBI modules to be used
use NeuroDB::DBI;
use NeuroDB::ExitCodes;
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

Documentation: perldoc DTIPrepRegister.pl

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
GetOptions(\@args_table, \@ARGV, \@args)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

# input option error checking
if ( !$profile ) {
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if  ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}
if (!$DTIPrep_subdir) {
    print STDERR "$Usage\n\tERROR: You must specify a DTIPrep subdirectory "
                 . "with processed files to be registered in the database.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
if (!$dti_file) {
    print STDERR "$Usage\n\tERROR: You must specify the raw DTI file that was "
                 . "processed through DTIPrep.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
if (!$DTIPrepProtocol) {
    print STDERR "$Usage\n\tERROR: You must specify the XML DTIPrep protocol "
                 . "used by DTIPrep.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}
if (!$DTIPrepVersion) {
    print STDERR "$Usage\n\tERROR: You must specify the version of DTIPrep "
                 . "used to process the DTI files.\n\n";
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}


# Establish database connection
my  $dbh    =   &NeuroDB::DBI::connect_to_db(@Settings::db);

# Needed for log file
my $data_dir = &NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath');
$data_dir    =~ s/\/$//;   # removing trailing / in $data_dir
my  $log_dir = "$data_dir/logs/DTIPrep_register";
system("mkdir -p -m 770 $log_dir") unless (-e $log_dir);
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my $date = sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $log  = "$log_dir/DTIregister$date.log";
open(LOG,">>$log");
print LOG "\n==> Successfully connected to database \n";
print LOG "Log file, $date\n\n";



# Fetch DTIPrep step during which a secondary QCed file will be created (for example: noMC for a file without motion correction). 
# This is set as a config option in the config file.
my  $QCed2_step = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'QCed2_step'
                    );


print LOG "\n==> DTI output directory is: $DTIPrep_subdir\n";




    #######################
    ####### Step 1: #######  Get the list of output files
    #######################

# 1.a Read the DTIPrep XML protocol into a hash
my ($protXMLrefs)   = &DTI::readDTIPrepXMLprot($DTIPrepProtocol);
if (!$protXMLrefs) {
    print LOG "\n\tERROR: DTIPrep XML protocol could not be read.\n";
    exit $NeuroDB::ExitCodes::UNREADABLE_FILE;
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
    print LOG "\nERROR:\n\tCould not determine a list of outputs for "
              . "$dti_file.\n";
    exit $NeuroDB::ExitCodes::GET_OUTPUT_LIST_FAILURE;
}
if ((!$mincdiffVersion) && ($DTIrefs->{$dti_file}->{'Postproc'}->{'Tool'} eq "mincdiffusion")) {
    print LOG "\n$Usage\nERROR:\n\tYou must specify which version of "
              . "mincdiffusion tools was used to post-process the DTI.\n";
    exit $NeuroDB::ExitCodes::MISSING_TOOL_VERSION;
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
    exit $NeuroDB::ExitCodes::MISSING_FILES;
}
# If $QCed2_step is set, QCed2_minc should be defined in %mri_files hash! 
if  (($QCed2_step) && (!$mri_files->{'Preproc'}{'QCed2'}{'minc'})) {
    print LOG "\nERROR:\n\tSecondary QCed DTIPrep nrrd & minc outputs are "
              . "missing in $DTIPrep_subdir.\n";
    exit $NeuroDB::ExitCodes::MISSING_FILES;
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
    exit $NeuroDB::ExitCodes::INSERT_FAILURE;
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
    exit $NeuroDB::ExitCodes::INSERT_FAILURE;
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
    exit $NeuroDB::ExitCodes::INSERT_FAILURE;
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
exit $NeuroDB::ExitCodes::SUCCESS;









#############
# Functions #
#############

=pod

=head3 register_XMLProt($XMLProtocol, $data_dir, $tool)

Registers XML protocol file into the C<mri_processing_protocol> table. It will
first check if protocol file was already registered in the database. If the
protocol file is already registered in the database, it will return the
Process Protocol ID from the database. If the protocol file is not registered
yet in the database, it will register it in the database and return the
C<ProcessProtocolID> of the registered protocol file.

INPUTS:
  - $XMLProtocol: XML protocol file of C<DTIPrep> to be registered
  - $data_dir   : data directory from the C<Config> table, tool name of the
                   protocol (a.k.a. C<DTIPrep>)

RETURNS: ID of the registered protocol file

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

=head3 registerProtocol($protocol, $md5sum, $tool, $data_dir)

Registers protocol file into C<mri_processing_protocol> table and move the
protocol to the C<$data_dir/protocols/DTIPrep> folder.

INPUTS:
  - $protocol: protocol file to be registered
  - $md5sum  : MD5 sum of the protocol file to be registered
  - $tool    : tool of the protocol file (C<DTIPrep>)
  - $data_dir: data directory (C</data/$PROJECT/data>)

RETURNS: ID of the registered protocol file

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

=head3 fetchProtocolID($md5sum)

Fetches the protocol ID in the C<mri_processing_protocol> table based on
the XML protocol's MD5 sum.

INPUT: MD5 sum of the XML protocol

RETURNS: ID of the registered protocol file

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

=head3 register_minc($minc, $raw_file, $data_dir, $inputs, $pipelineName, $toolName, $registeredXMLFile, $registeredQCReportFile, $scanType, $registered_nrrd)

Sets the different parameters needed for MINC files' registration
and calls C<&registerFile> to register the MINC file in the database
via C<register_processed_data.pl> script.

INPUTS:
  - $minc                  : MINC file to be registered
  - $raw_file              : source file of the MINC file to register
  - $data_dir              : data_dir directory from the config table
  - $inputs                : input files of the file to be registered
  - $pipelineName          : name of the pipeline used to obtain the MINC file
  - $toolName              : tool name and version used
  - $registeredXMLFile     : registered C<DTIPrep> XML report
  - $registeredQCReportFile: registered C<DTIPrep> text report
  - $scanType              : scan type of the MINC file to register
  - $registered_nrrd       : optional, registered NRRD file used to create the MINC file

RETURNS: registered MINC file on success, undef otherwise

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

=head3 register_XMLFile($XMLFile, $raw_file, $data_dir, $QCReport, $inputs, $pipelineName, $toolName)

Sets parameters needed to register the XML report/protocol of C<DTIPrep>
and calls registerFile to register the XML file via register_processed_data.pl.

INPUTS:
  - $XMLFile     : XML file to be registered
  - $raw_file    : native DWI file used to obtain the C<DTIPrep> outputs
  - $data_dir    : data directory (e.g. C</data/$PROJECT/data>)
  - $QCReport    : C<DTIPrep> QC text report
  - $inputs      : input files used to process data through C<DTIPrep>
  - $pipelineName: pipeline name used to process DWIs (C<DTIPrepPipeline>)
  - $toolName    : C<DTIPrep> name and version used to process the DWI file

RETURNS: the registered XNL file if it was registered in the database or undef

=cut

sub register_XMLFile {
    my ($XMLFile, $raw_file, $data_dir, $QCReport, $inputs, $registeredXMLprotocolID, $pipelineName, $toolName) =   @_;

    print LOG "\n==> File to register is:\n$XMLFile\n";
    print "\n==>File: $XMLFile\n";

    my  $src_name   = basename($raw_file, '.mnc');
    my  $src_fileID = &getFileID($XMLFile, $src_name);

    my  ($src_pipeline, $src_tool);
    if  (!$toolName)    {
        print STDERR "WARNING: This should not happen as long as the pipeline "
                     . "versioning of DTIPrep is not fixed!";
        exit $NeuroDB::ExitCodes::MISSING_TOOL_VERSION;
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

=head3 register_QCReport($QCReport, $raw_file, $data_dir, $inputs, $pipelineName, $toolName)

Sets parameters needed to register the QCreport of C<DTIPrep> and calls
C<&registerFile> to register the QCreport file via
C<register_processed_data.pl>.

INPUTS:
  - $QCReport    : QC report file to be registered
  - $raw_file    : native DWI file used to obtain the C<DTIPrep> outputs
  - $data_dir    : data directory (e.g. C</data/$PROJECT/data>)
  - $inputs      : input files used to process data through C<DTIPrep>
  - $pipelineName: pipeline name used to process DTIs (C<DTIPrepPipeline>)
  - $toolName    : C<DTIPrep> name and version used to process the DWI file

RETURNS: registered QCReport file if it was registered in the database or undef

=cut

sub register_QCReport {
    my ($QCReport, $raw_file, $data_dir, $inputs, $registeredXMLprotocolID, $pipelineName, $toolName)    =   @_;

    print LOG "\n==> File to register is:\n$QCReport\n";
    print "\n==>File: $QCReport\n";

    my  $src_name   = basename($raw_file, '.mnc');
    my  $src_fileID = &getFileID($QCReport,$src_name);

    my  ($src_pipeline, $src_tool);
    if  (!$toolName)    {
        print STDERR "WARNING: This should not happen as long as the pipeline "
                     . "versioning of DTIPrep is not fixed!";
        exit $NeuroDB::ExitCodes::MISSING_TOOL_VERSION;
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

=head3 getFiles($dti_file, $DTIrefs)

This function checks that all the processing files exist on the filesystem and
returns the files to be inserted in the database. When NRRD and MINC files are
found, it will only return the MINC file. (NRRD files will be linked to the
MINC file when inserting files in the database).

INPUTS:
  - $dit_file: raw DTI dataset that is used as a key in C<$DTIrefs> hash
  - $DTIref  : hash containing all output paths and tool information

RETURNS:
  - $XMLProtocol    : C<DTIPrep> XML protocol found in the file system
  - $QCReport       : C<DTIPrep> QC text report found in the file system
  - $XMLReport      : C<DTIPrep> QC XML report found in the file system
  - $QCed_minc      : QCed MINC file created after conversion of QCed NRRD file
  - $RGB_minc       : RGB MINC file found in the file system
  - $FA_minc        : FA MINC file found in the file system
  - $MD_minc        : MD MINC file found in the file system
  - $baseline_minc  : baseline MINC file found in the file system
  - $brain_mask_minc: brain mask MINC file found in the file system
  - $QCed2_minc     : optional, secondary QCed MINC file created after
                       conversion of secondary QCed C<DTIPrep> NRRD file
  - returns undef if there are some missing files (except for C<QCed2_minc>
     which is optional)

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

=head3 checkPreprocessFiles($dti_file, $DTIrefs, $mri_files)

Function that checks if all C<DTIPrep> pre-processing files are present in the
file system.

INPUTS:
  - $dti_file: raw DTI dataset that is used as a key in C<$DTIrefs> hash
  - DTIrefs  : hash containing all output paths and tool information
  - mri_files: list of processed outputs to register or that have been
                registered

RETURNS:
  - $XMLProtocol: C<DTIPrep> XML protocol found in the file system
  - $QCReport   : C<DTIPrep> text QC report found in the file system
  - $XMLReport  : C<DTIPrep> XML QC report found in the file system
  - $QCed_minc  : QCed MINC file created after conversion of QCed NRRD file
  - $QCed2_minc : optional, secondary QCed MINC file created after
                   conversion of secondary QCed C<DTIPrep> NRRD file
  - returns undef if one of the file listed above is missing (except
     for C<QCed2_minc> which is optional)

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

=head3 checkPostprocessFiles($dti_file, $DTIrefs, $mri_files)

Function that checks if all postprocessing files (from C<DTIPrep> or
C<mincdiffusion>) are present in the file system.

INPUTS:
  - $dti_file : raw DTI dataset that is used as a key in C<$DTIrefs> hash
  - $DTIrefs  : hash containing all output paths and tool information
  - $mri_files: list of processed outputs to register or that have been registered

RETURNS:
  - $RGB_minc       : RGB map
  - $FA_minc        : FA map
  - $MD_minc        : MD map
  - $baseline_minc  : baseline (or frame-0) map
  - $brain_mask_minc: brain mask produced by C<mincdiffusion> tools (not
                       available if C<DTIPrep> was run to obtain the
                       post-processing outputs)
  - will return undef if one of the file listed above is missing

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

=head3 getFileID($file, $src_name)

Fetches the source FileID from the database based on the C<$src_name> file
identified by C<getFileName>.

INPUTS:
  - $file    : output filename
  - $src_name: source filename (file that has been used to obtain C<$file>)

RETURNS: source File ID (file ID of the source file that has been used to
          obtain $file)

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

=head3 getToolName($file)

Fetches tool information stored either in the MINC file's header or in the
QC text report.

INPUT: MINC or QC text report to look for tool information

RETURNS:
  - $src_pipeline: name of the pipeline used to obtain C<$file> (C<DTIPrepPipeline>)
  - $src_tool    : name and version of the tool used to obtain C<$file>
                    (C<DTIPrep_v1.1.6>, C<mincdiffusion_v...>)

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
        print LOG "ERROR: no tool have been found in mincheader of $file. "
                  . "Check that the processing:pipeline field exits or specify "
                  . "which tool was used manually with the option "
                  . "-DTIPrepVersion or -mincdiffusionVersion as input of the "
                  . "script DTIPrepRegister.pl.";
        exit $NeuroDB::ExitCodes::MISSING_TOOL_VERSION;
    }else   {
        #remove leading spaces, trailing spaces and all instances of "
        $src_tool       =~s/"//g;
        $src_pipeline   =~s/"//g;
    }
    
    return  ($src_pipeline, $src_tool);
}


=pod

=head3 getPipelineDate($file, $data_dir, $QCReport)

Fetches the date at which the C<DTIPrep> pipeline was run either in the processed
MINC file's header or in the QC text report.

INPUTS:
  - $file    : MINC or QC text report to look for tool information
  - $data_dir: data directory (e.g. C</data/$PROJECT/data>)
  - $QCReport: QC text report created when C<$file> was created

RETURNS: date at which the pipeline has been run to obtain C<$file>

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

=head3 insertReports($minc, $registeredXMLFile, $registeredQCReportFile)

Inserts the path to C<DTIPrep>'s QC text, XML reports and XML protocol in the
MINC file's header.

INPUTS:
  - $minc                  : MINC file for which the header should be modified
  - $registeredXMLfile     : path to the registered C<DTIPrep>'s QC XML report
  - $registeredQCReportFile: path to the registered C<DTIPrep>'s QC text report

RETURNS:
 - $Txtreport_insert: 1 on text report path insertion success, undef otherwise
 - $XMLreport_insert: 1 on XML report path insertion success, undef otherwise

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

=head3 insertPipelineSummary($minc, $data_dir, $XMLReport, $scanType)

Inserts in the MINC header a summary of C<DTIPrep> reports. This summary consists
of the directions rejected due to slice wise correlation, the directions
rejected due to interlace correlation, and the directions rejected due to
gradient wise correlation.

INPUTS:
  - $minc     : MINC file in which the summary will be inserted
  - $data_dir : data directory (e.g. C</data/$PROJECT/data>)
  - $XMLReport: C<DTIPrep>'s XML QC report from which the summary will be extracted

RETURNS: 1 on success, undef on failure

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

=head3 registerFile($file, $src_fileID, $src_pipeline, $src_tool, $pipelineDate, $coordinateSpace, $scanType, $outputType, $inputs)

Registers file into the database via C<register_processed_data.pl> with all
options.

INPUTS:
  - $file           : file to be registered in the database
  - $src_fileID     : source file's FileID
  - $src_pipeline   : pipeline used to obtain the file (C<DTIPrepPipeline>)
  - $src_tool       : name and version of the tool (C<DTIPrep> or C<mincdiffusion>)
  - $pipelineDate   : file's creation date (= pipeline date)
  - $coordinateSpace: file's coordinate space (= native, T1 ...)
  - $scanType       : file's scan type (= C<DTIPrepReg>, C<DTIPrepDTIFA>,
                       C<DTIPrepDTIMD>, C<DTIPrepDTIColorFA>...)
  - $outputType     : file's output type (C<.xml>, C<.txt>, C<.mnc>...)
  - $inputs         : input files that were used to create the file to
                       be registered (intermediary files)

RETURNS: registered file

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

=head3 fetchRegisteredFile($src_fileID, $src_pipeline, $pipelineDate, $coordinateSpace, $scanType, $outputType)

Fetches the registered file from the database to link it to the MINC files.

INPUTS:
 - $src_fileID     : FileID of the source native file
 - $src_pipeline   : pipeline name used to register the processed file
 - $pipelineDate   : pipeline data used to register the processed file
 - $coordinateSpace: processed file's coordinate space
 - $scanType       : scan type used to register the processed file
 - $outputType     : output type used to register the processed file

RETURNS: path to the registered processed file

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

=head3 register_DTIPrep_files($minc, $nrrd, $raw_file, $data_dir, $inputs, $registeredXMLProtocolID, $pipelineName, $DTIPrepVersion, $registeredXMLReportFile, $registeredQCReport, $scanType)

Registers C<DTIPrep> NRRD and MINC files. The MINC file will have a link to the
registered NRRD file (C<&register_minc> function will modify the MINC header to
include this information) in addition to the links toward QC reports and
protocol.

INPUTS:
  - $minc                   : MINC file to be registered
  - $nrrd                   : NRRD file to be registered
  - $raw_file               : raw DWI file used to create the MINC file to
                               register
  - $data_dir               : data directory (e.g. C</data/$PROJECT/data>)
  - $inputs                 : input files that were used to create the file to
                               be registered (intermediary files)
  - $registeredXMLProtocolID: registered XML protocol file
  - $pipelineName           : name of the pipeline that created the file to be
                               registered (C<DTIPrepPipeline>)
  - $DTIPrepVersion         : C<DTIPrep>'s version
  - $registeredXMLReportFile: registered QC XML report file
  - $registeredQCReport     : registered QC text report file
  - $scanType               : scan type to use to label/register the MINC file


RETURNS: registered MINC files or undef on insertion's failure

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

=head3 register_nrrd($nrrd, $raw_file, $data_dir, $QCReport, $inputs, $pipelineName, $toolName, $scanType)

Sets parameters needed to register the NRRD file produced by C<DTIPrep>
and calls registerFile to register the NRRD file via
C<register_processed_data.pl>.

INPUTS:
  - $nrrd        : NRRD file to be registered
  - $raw_file    : native DWI file used to obtain the C<DTIPrep> outputs
  - $data_dir    : data directory (e.g. C</data/$PROJECT/data>)
  - $QCReport    : C<DTIPrep> QC text report
  - $inputs      : input files used to process data through C<DTIPrep>
  - $pipelineName: pipeline name used to process DTIs (C<DTIPrepPipeline>)
  - $toolName    : C<DTIPrep> name and version used to process the DWI file
  - $scanType    : NRRD file's scan type

RETURNS: registered NRRD file or undef on insertion's failure

=cut

sub register_nrrd {
    my ($nrrd, $raw_file, $data_dir, $QCReport, $inputs, $registeredXMLprotocolID, $pipelineName, $toolName, $scanType) =   @_;

    print LOG "\n==> File to register is:\n$nrrd\n";
    print "\n==>File: $nrrd\n";

    my  $src_name   = basename($raw_file, '.mnc');
    my  $src_fileID = &getFileID($nrrd, $src_name);

    my  ($src_pipeline, $src_tool);
    if  (!$toolName)    {
        print STDERR "WARNING: This should not happen as long as the pipeline "
                     . "versioning of DTIPrep is not fixed!";
        exit $NeuroDB::ExitCodes::MISSING_TOOL_VERSION;
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

=head3 register_Preproc($mri_files, $dti_file, $data_dir, $pipelineName, $toolName, $process_step, $proc_file)

Gathers all C<DTIPrep> preprocessed files to be registered in the database
and calls C<&register_DTIPrep_files> on all of them. Will register first the
NRRD file and then the MINC file for each scan type.

INPUTS:
  - $mri_files   : hash containing all DTI output information
  - $dti_file    : native DWI file (that will be used as a key
                    for C<$mri_files>)
  - $data_dir    : data directory (e.g. C</data/$PROJECT/data>)
  - $pipelineName: pipeline name (C<DTIPrepPipeline>)
  - $toolName    : tool's name and version
  - $process_step: processing step (C<Preproc> or C<Postproc>)
  - $proc_file   : processed file key (C<QCed>, C<QCed2>...)

RETURNS: path to the MINC file that was registered

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

=head3 register_images($mri_files, $raw_file, $data_dir, $pipelineName, $toolName, $process_step)

Function to register processed images in the database depending on the tool
used to obtain them. Will call C<&register_DTIPrep_files> if files to be
registered are obtained via C<DTIPrep> or C<&register_minc> if files to be
registered are obtained using C<mincdiffusion> tools.

INPUTS:
  - $mri_files   : hash with information about the files to be registered
  - $raw_file    : source raw image
  - $data_dir    : data directory (e.g. C</data/$PROJECT/data>)
  - $pipelineName: name of the pipeline used (a.k.a C<DTIPrep>)
  - $toolName    : tool's version and name
  - $process_step: processing step (pre-processing, post-processing)

RETURNS:
  - @registered        : list of registered files
  - @failed_to_register: list of files that failed to be registered in the DB

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

=head3 getInputList($mri_files, $data_dir, $process_step, $proc_file)

Function that will return in a string the list of inputs used to process the
data separated by ';'.

INPUTS:
  - $mri_files   : list of processed outputs to register or that
                    have been registered
  - $data_dir    : data directory (e.g. C</data/$PROJECT/data>)
  - $process_step: processing step used for the processed output
                    to determine inputs
  - $proc_file   : processing file to determine inputs used

RETURNS: string with each inputs used separated by ';'

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

=head3 fetchRegisteredMD5($md5sum)

Will check if MD5 sum has already been registered into the database.

INPUT: MD5 sum of the file

RETURNS:
  - $registeredFile    : registered FileID matching MD5 sum
  - $registeredScanType: scan type of the registered C<FileID> matching MD5 sum

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

__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut
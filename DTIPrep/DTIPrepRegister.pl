#! /usr/bin/perl

use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use FindBin;
use Date::Parse;
use lib "$FindBin::Bin";

use DB::DBI;
use DTI::DTI;

my  $profile        = undef;
my  $pipelineName;
my  $DTIPrep_subdir = undef;
my  @args;


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
    ["-profile",        "string",   1,      \$profile,      "name of config file in ~/.neurodb."],
    ["-pipelineName",   "string",   1,      \$pipelineName, "PipelineName_version of the pipeline used (i.e. DTIPrep_v1.1.6). This option should be set if the pipelineName is not stored in the mincheader field processing:src_pipeline of the processed file"],
    ["-DTIPrep_subdir", "string",   1,      \$DTIPrep_subdir,"DTIPrep subdirectory where processed files to be registered in the database are stored"],
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

if  (!$pipelineName)    {
    print "$Usage\n\tERROR: This is broken as long as Pipeline versioning is not fixed in DTIPrep. You have to specify the option -pipelineName and set the version that was used!.\n\n";  
    exit 33;
}

if  (!$DTIPrep_subdir)    {
    print "$Usage\n\tERROR: You must specify a DTIPrep subdirectory with processed files to be registered in the database.\n\n";
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

# Suffix used in DTIPrep protocol to create secondary output like a DWI file without motion correction, eddy current correction etc... If defined in the config file, will insert this dataset in addition to the default QCed one. Otherwise, will just insert the default QCed file in the database.
my  $QCed2_suffix=  $Settings::QCed2_suffix;

# establish database connection
my  $dbh    =   &DB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";


print LOG "\n==> DTI output directory is: $DTIPrep_subdir\n";

    #######################
    ####### Step 1: #######  Get output files to be registered in the database
    #######################
    # (QCed2 is an optional second file produced by DTIPrep without, for example, motion correction done)
my  ($QCed, $RGB, $FA, $MD, $baseline, $brain_mask, $QCReport, $XMLReport, $XMLProtocol, $QCed2)   =   getFiles($DTIPrep_subdir, $QCed2_suffix);
# $QCed will be undefined if one of the expected output filed was not found
if  (!$QCed) {
    print LOG "\nERROR:\n\tCould not find all outputs to be registered in the database. Exit now.\n print LOG ";
    exit 0;
}

    #######################
    ####### Step 2: #######  Register the XML report
    #######################
    # $registeredXMLReportFile will store the path to the registered XMLReportFile
my ($registeredXMLReportFile) = register_XMLFile($XMLReport,$QCReport,$pipelineName) if ($XMLReport);
if (!$registeredXMLReportFile) {
    print LOG "\nERROR: no XML report file was registered in the database\n";
    exit 0;
} else {
    print LOG "\nRegistered XML report $registeredXMLReportFile.\n";
}

    #######################
    ####### Step 3: #######  Register the QC report
    #######################
    # $registeredQCReportFile will store the path to the registered QCReportFile
my ($registeredQCReportFile)  = register_QCReport($QCReport,$pipelineName)    if ($QCReport);
if (!$registeredQCReportFile) {
    print LOG "\nERROR: no QC report file was registered in the database\n";
    exit 0;
} else {
    print LOG "\nRegistered QC report $registeredQCReportFile.\n";
}
    
    #######################
    ####### Step 4: #######  Register the XML protocol file used by DTIPrep
    #######################
    # $registeredXMLprotocolFile will store the path to the registered XMLprotocolFile
my ($registeredXMLprotocolFile)   = register_XMLFile($XMLprotocol, $QCReport, $pipelineName) if ($XMLprotocol);
if (!$registeredXMLprotocolFile) {
    print LOG "\nERROR: no XML protocol file was registered in the database\n";
    exit 0;
} else {
    print LOG "\nRegistered XML protocol $registeredXMLprotocolFile.\n";
}

    #######################
    ####### Step 5: #######  Register QCed minc files with associated reports and nrrd files
    #######################
    
my  ($registeredQCedFile)   = register_minc($QCed, $QCReport, $pipelineName, $registeredXMLReportFile, $registeredQCReportFile, $registeredXMLprotocolFile)   if ($QCed && -e $QCed);

my  ($registeredRGBFile)    = register_minc($RGB,  $QCReport, $pipelineName, $registeredXMLReportFile, $registeredQCReportFile, $registeredXMLprotocolFile)   if ($RGB  && -e $RGB) ;

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
    my ($minc, $QCReport, $pipelineName, $registeredXMLFile, $registeredQCReportFile, $registeredXMLprotocolFile)  =   @_;

    print LOG "\n==> File to register is:\n$minc\n";
    print "\n==>File: $minc\n";

    my  $src_name   =   getSourceFileName($minc,$dbh);
    my  $src_fileID =   getSourceFileID($minc,$src_name,$dbh);
    
    my  $src_pipeline;
    if  (!$pipelineName)    {
        # need to develop this later once DTIPrep versioning will be reported into QC reports.
        ($src_pipeline)   =   getPipelineName($minc);
    }else   {
        $src_pipeline     =   $pipelineName;
        # insert pipelineName into the mincheader.
        DTI::modify_header('processing:pipeline', 
                           $src_pipeline, 
                           $minc);
    }
    
    my  ($pipelineDate) =   getPipelineDate($minc,$QCReport); # if date not in $minc, use QC report and insert it into the mincheader.
    
    insertPipelineReports($minc, $registeredXMLFile, $registeredQCReportFile, $registeredXMLprotocolFile);
    insertPipelineSummary($minc, $QCReport);

    my  ($coordinateSpace);
    my  ($scanType);
    if      ($minc=~/rgb\.mnc$/i) {
        $coordinateSpace    =   "nativeT1";
        $scanType           =   "RGBqc";
    } elsif ($minc=~/QCed\.mnc$/i) {
        $coordinateSpace    =   "native";
        $scanType           =   "QCedDTI";
    }        
    
    my $outputType  =   "qc";

    if  (($minc)            &&  ($src_fileID)      && 
         ($src_pipeline)    &&  ($pipelineDate)    && 
         ($coordinateSpace) &&  ($scanType)        && 
         ($outputType))     { 

        my  ($registeredMincFile)   = registerFile($minc, 
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

    }    

}   

=pod
This set the different parameters needed to be able to register XML Report and protocol of DTIPrep. 
Once set, this function will call registerFile which will run register_processed_data.pl.
=cut
sub register_XMLFile {
    my ($XMLFile, $QCReport, $pipelineName) =   @_;

    print LOG "\n==> File to register is:\n$XMLFile\n";
    print "\n==>File: $XMLFile\n";

    my  $src_name   =   getSourceFileName($XMLFile, $dbh);
    my  $src_fileID =   getSourceFileID($XMLFile, $src_name, $dbh);

    my  $src_pipeline;
    if  (!$pipelineName)    {
        print "WARNING: This should not happen as long as the pipeline versioning of DTIPrep is not fixed!"; 
        exit 33; 
        # Will need to program this part once DTIPrep fixed!
        #($src_pipeline)=getPipelineName($XMLFile);
    }else   {
        $src_pipeline   =   $pipelineName;
    }

    my ($pipelineDate)  =   getPipelineDate($XMLFile, $QCReport);

    my $coordinateSpace =   "native";
    my ($scanType, $outputType);
    if ($XMLFile =~ /XMLQCResult\.xml$/i) {
        $scanType       =   "XMLQCReport";
        $outputType     =   "qcreport";
    } elsif ($XMLFile =~ /XMLnobcheck_prot\.xml$/i) {
        $scanType       =   "ProcessingProtocol";
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

    }
}        

=pod
This set the different parameters needed to be able to register QCReports of DTIPrep. 
Once set, this function will call registerFile which will run register_processed_data.pl.
=cut
sub register_QCReport {
    my ($QCReport,$pipelineName)    =   @_;

    print LOG "\n==> File to register is:\n$QCReport\n";
    print "\n==>File: $QCReport\n";

    my  $src_name   =   getSourceFileName($QCReport,$dbh);
    my  $src_fileID =   getSourceFileID($QCReport,$src_name,$dbh);

    my  $src_pipeline;
    if  (!$pipelineName)    {
        print "WARNING: This should not happen as long as the pipeline versioning of DTIPrep is not fixed!"; 
        exit 33; 
        # Will need to program this part once DTIPrep fixed!
        #($src_pipeline)=getPipelineName($QCReport);
    }else   {
        $src_pipeline =   $pipelineName;
    }

    my ($pipelineDate)  =   getPipelineDate($QCReport,$QCReport);

    my $coordinateSpace =   "native";
    my $scanType        =   "TxtQCReport";
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
        
    }

}        
        
=pod
This function fetches the files to be inserted in the database.
=cut
sub getFiles {
    my  ($DTIPrep_subdir, $QCed2_suffix)   =   @_;

    opendir(DIR,$DTIPrep_subdir) || die "Cannot open $DTIPrep_subdir\n";
    my  @entries = readdir(DIR);
    closedir(DIR);

    my  ($QCed_name)        = grep( /QCed\.mnc$/i,              @entries);
    my  ($RGB_name)         = grep( /rgb\.mnc$/i,               @entries);
    my  ($FA_name)          = grep( /FA\.mnc$/i,                @entries);
    my  ($MD_name)          = grep( /MD\.mnc$/i,                @entries);
    my  ($baseline_name)    = grep( /frame0\.mnc$/i,            @entries);
    my  ($brain_mask_name)  = grep( /mask-diffspace\.mnc$/i,    @entries);
    my  ($QCReport_name)    = grep( /QCReport\.txt$/i,          @entries);
    my  ($XMLReport_name)   = grep( /XMLQCResult\.xml$/i,       @entries);
    my  ($XMLProtocol_name) = grep( /XMLnobcheck_prot\.xml$/i,  @entries);
    # optionaly inserts a secondary file produced by DTIPrep without, for example, motion correction.
    my  ($QCed2_name)       = grep( /$QCed2_suffix\.mnc$/i,     @entries)   if ($QCed2_suffix);
    
    my  $QCed       =   $DTIPrep_subdir."/".$QCed_name;
    my  $RGB        =   $DTIPrep_subdir."/".$RGB_name;
    my  $FA         =   $DTIPrep_subdir."/".$FA_name;
    my  $MD         =   $DTIPrep_subdir."/".$MD_name;
    my  $baseline   =   $DTIPrep_subdir."/".$baseline_name;
    my  $brain_mask =   $DTIPrep_subdir."/".$brain_mask_name;
    my  $QCReport   =   $DTIPrep_subdir."/".$QCReport_name;
    my  $XMLReport  =   $DTIPrep_subdir."/".$XMLReport_name;
    my  $XMLProtocol=   $DTIPrep_subdir."/".$XMLProtocol_name;
    my  $QCed2      =   $DTIPrep_subdir."/".$QCed2_name     if ($QCed2_suffix);

    # return undef if could not find $QCed2 (when $QCed2_suffix was defined) 
    return undef if (($QCed2_suffix) && (!$QCed2));

    # return all output files if could all be found, undef otherwise
    if (($QCed) && ($RGB) && ($FA) && ($MD) && ($baseline) && ($brain_mask) 
             && ($QCReport) && ($XMLReport) && ($XMLProtocol)))
        return  ($QCed, $RGB, $FA, $MD, $baseline, $brain_mask, $QCReport, $XMLReport, $XMLProtocol, $QCed2);
    } else {
        return undef;
    }
}

=pod
This function gathers informations about the source file (i.e. raw dataset that was used to obtain the minc file)
=cut
sub getSourceFileName {
    my  ($file, $dbh)   =   @_;

    my  $src    =  $file;
    if ($file=~/\.mnc/)    {
        my $val =   DTI::fetch_header_info('processing:sourceFile',
                                           $file,
                                           '$3');
        $val    =~  s/"//g  unless (!$val);
        $src    =   $val    unless (!$val);
    }
    $src        =~  s/(_QCReport\.txt|_XMLQCResult\.xml|_XMLnobcheck_prot\.xml|_QCed\.mnc|_QCed_rgb\.mnc)$//;
    my $src_name=   basename($src,'.mnc');

    return ($src_name);
}

=pod
Fetches the source FileID from the database based on the src_name file identified by getSourceFileName.
=cut
sub getSourceFileID {
    my  ($file,$src_name,$dbh)    =   @_;

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
    my  ($file,$QCReport)   =   @_;
    
    my  $pipelineDate;
    
    if  ($file=~/\.mnc/)    {
        $pipelineDate   =   DTI::fetch_header_info('processing:processing_date',
                                                   $file,
                                                   '$3');
    }
    
    if  ((!$pipelineDate) || ($file=~/XMLQCResult\.xml/) || ($file=~/QCReport\.txt/))   {
    
        print LOG "\n> Fetching date of processing in the QCReport.txt file created by DTIPrep";
        my  $check_line = `cat $QCReport|grep "Check Time"`;
        $check_line     =~s/Check Time://;      # Only keep date info in $check_line.
        #use Date::Parse library to read the date
        my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($check_line);
        $pipelineDate   =  sprintf("%4d%02d%02d",$year+1900,$month+1,$day);
        
        if ($file=~/\.mnc/) {
            # insert pipelineDate into mincheader if not already in the mincheader. 
            DTI::modify_header('processing:processing_date', 
                               $pipelineDate, 
                               $file);
        }
    
    } else  {
        
        print LOG "\n> Fetching date of processing in the mincheader of $file";
        #remove leading spaces, trailing spaces and all instances of "
        $pipelineDate   =~s/"//g;
    
    }
    
    return  ($pipelineDate);
}

=pod
Insert in the mincheader the path to DTIPrep QC txt and xml reports.
=cut
sub insertPipelineReports {
    my ($minc, $registeredXMLFile, $registeredQCReportFile, $registeredXMLprotocolFile) = @_;

    DTI::modify_header('processing:DTIPrepTxtReport',   $registeredQCReportFile, $minc) if ($registeredQCReportFile);

    DTI::modify_header('processing:DTIPrepXmlReport',   $registeredXMLFile, $minc)      if ($registeredXMLFile);
    DTI::modify_header('processing:DTIPrepXmlProtocol', $registeredXMLprotocolFile, $minc)      if ($registeredXMLFile);

}

=pod
Insert in the mincheader the summary of DTIPrep reports.
=cut
sub insertPipelineSummary   {
    my ($minc,$QCReport)   =   @_;

    my ($rm_slicewise,$rm_interlace,$rm_intergradient)  =   getRejectedDirections($QCReport);
    
    my $count_slice     =   insertHeader($minc, $rm_slicewise,      "processing:slicewise_rejected");
    my $count_inter     =   insertHeader($minc, $rm_interlace,      "processing:interlace_rejected");
    my $count_gradient  =   insertHeader($minc, $rm_intergradient,  "processing:intergradient_rejected");

    my $total           =   $count_slice + $count_inter + $count_gradient;
    DTI::modify_header('processing:total_rejected',
                       $total,
                       $minc);
}

=pod
Get the list of directions rejected by DTI per type (i.e. slice-wise correlations, inter-lace artifacts, inter-gradient artifacts).
=cut
sub getRejectedDirections   {
    my ($QCReport)  =   @_;

    ## these are the unique directions that were rejected due to slice-wise correlations
    my $rm_slicewise    =   `cat $QCReport | grep whole | sort -k 2,2 -u | awk '{print \$2}'|tr '\n' ','`;
    ## these are the unique directions that were rejected due to inter-lace artifacts
    my $rm_interlace    =   `cat $QCReport | sed -n -e '/Interlace-wise Check Artifacts/,/================================/p' | grep '[0-9]' | sort -k 1,1 -u | awk '{print \$1}'|tr '\n' ','`;
    ## these are the unique directions that were rejected due to inter-gradient artifacts
    my $rm_intergradient     =   `cat $QCReport | sed -n -e '/Inter-gradient check Artifacts::/,/================================/p' | grep '[0-9]'| sort -k 1,1 -u  | awk '{print \$1}'|tr '\n' ','`;
    
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
        $value  =   "@rm_dirs ($count_dirs)";
    } else  {
        $value  =   "Directions @rm_dirs ($count_dirs)";
    }    
    DTI::modify_header($minc_field,
                       $value,
                       $minc);

    return  ($count_dirs);
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
                    "-sourcePipeline $pipelineName " .
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

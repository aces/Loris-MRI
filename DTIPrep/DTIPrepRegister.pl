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

my  $profile = undef;
my  $pipelineName;
my  $xml=0;
my  $txt=0;
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
    ["-xml",            "boolean",  undef,  \$xml,          "insert DTIPrep .xml QC report in the database"],
    ["-txt",            "boolean",  undef,  \$txt,          "insert the DTIPrep .txt QC report in the database"],
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

# needed for log file
my  $data_dir    =  $Settings::data_dir;
my  $log_dir     =  "$data_dir/logs/DTIPrep_register";
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my  $date        =  sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log         =  "$log_dir/DTIregister$date.log";
open(LOG,">>$log");
print LOG "Log file, $date\n\n";

# establish database connection
my  $dbh    =   &DB::DBI::connect_to_db(@Settings::db);
print LOG "\n==> Successfully connected to database \n";


## read input from STDIN, store into array @DTIPrep_subdirs (`find ....... | this_script`)
my @DTIPrep_subdirs = <STDIN>; chomp @DTIPrep_subdirs;

## foreach directory, get the files needed and register them in the database
foreach my  $DTIPrep_subdir  (@DTIPrep_subdirs)   {

    print LOG "\n==> DTI outputs directory: $DTIPrep_subdir\n";

    # Get the DTI output files (i.e. QCed.mnc, QCReport.txt and RGB.mnc)
    my  ($QCReport,$XMLReport,$RGB,$QCed)   =   getFiles($DTIPrep_subdir);
    my  ($registeredXMLFile, $registeredQCReportFile);
    
    # What to do with the XML when -xml option is set
    if      (($xml == 1) && (!$XMLReport))  {
        print LOG "WARNING: No XML Report was found in $DTIPrep_subdir\n\n\n";
    }elsif  (($xml == 1) && ($XMLReport))   {
        $registeredXMLFile      = register_XMLReport($XMLReport,$QCReport,$pipelineName);
        print "\nRegistered XML report = $registeredXMLFile.\n";
    }

    # What to do with the QCReport when -txt option is set
    if      (($txt == 1) && (!$QCReport))   {
        print LOG "WARNING: No QCReport file was found in $DTIPrep_subdir\n\n\n";
    }elsif  (($txt == 1) && ($QCReport))    {
        $registeredQCReportFile = register_QCReport($QCReport,$pipelineName);
        print "\nRegistered QC report = $registeredQCReportFile.\n";
    }

    if  ($registeredXMLFile && $registeredQCReportFile) {
        my  ($registeredRGBFile)    = register_minc($RGB,  $QCReport, $pipelineName, $registeredXMLFile, $registeredQCReportFile)   if ($RGB  && -e $RGB) ;
        my  ($registeredQCedFile)   = register_minc($QCed, $QCReport, $pipelineName, $registeredXMLFile, $registeredQCReportFile)   if ($QCed && -e $QCed);
    } elsif ($registeredXMLFile && !$registeredQCReportFile) {
        my  ($registeredRGBFile)    = register_minc($RGB,  $QCReport, $pipelineName, $registeredXMLFile, undef)   if ($RGB  && -e $RGB) ;
        my  ($registeredQCedFile)   = register_minc($QCed, $QCReport, $pipelineName, $registeredXMLFile, undef)   if ($QCed && -e $QCed);
    } elsif (!$registeredXMLFile && $registeredQCReportFile) {  
        my  ($registeredRGBFile)    = register_minc($RGB,  $QCReport, $pipelineName, undef, $registeredQCReportFile)   if ($RGB  && -e $RGB) ;
        my  ($registeredQCedFile)   = register_minc($QCed, $QCReport, $pipelineName, undef, $registeredQCReportFile)   if ($QCed && -e $QCed);
    } else {
        my  ($registeredRGBFile)    = register_minc($RGB,  $QCReport, $pipelineName, undef, undef)   if ($RGB  && -e $RGB) ;
        my  ($registeredQCedFile)   = register_minc($QCed, $QCReport, $pipelineName, undef, undef)   if ($QCed && -e $QCed);
    }
}

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
    my ($minc, $QCReport, $pipelineName, $registeredXMLFile, $registeredQCReportFile)  =   @_;

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
    
    insertPipelineReports($minc, $registeredXMLFile, $registeredQCReportFile);
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
This set the different parameters needed to be able to register XMLReports of DTIPrep. 
Once set, this function will call registerFile which will run register_processed_data.pl.
=cut
sub register_XMLReport {
    my ($XMLReport,$QCReport,$pipelineName) =   @_;

    print LOG "\n==> File to register is:\n$XMLReport\n";
    print "\n==>File: $XMLReport\n";

    my  $src_name   =   getSourceFileName($XMLReport,$dbh);
    my  $src_fileID =   getSourceFileID($XMLReport,$src_name,$dbh);

    my  $src_pipeline;
    if  (!$pipelineName)    {
        print "WARNING: This should not happen as long as the pipeline versioning of DTIPrep is not fixed!"; 
        exit 33; 
        # Will need to program this part once DTIPrep fixed!
        #($src_pipeline)=getPipelineName($XMLReport);
    }else   {
        $src_pipeline   =   $pipelineName;
    }

    my ($pipelineDate)  =   getPipelineDate($XMLReport,$QCReport);

    my $coordinateSpace =   "native";
    my $scanType        =   "XMLQCReport";
    my $outputType      =   "qcreport";

    if  (($XMLReport)       &&  ($src_fileID)      &&
         ($src_pipeline)    &&  ($pipelineDate)    &&
         ($coordinateSpace) &&  ($scanType)        &&
         ($outputType))     {

        my  ($registeredXMLFile)  = registerFile($XMLReport,
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
    my  ($DTIPrep_subdir)   =   @_;

    opendir(DIR,$DTIPrep_subdir) || die "Cannot open $DTIPrep_subdir\n";
    my  @entries = readdir(DIR);
    closedir(DIR);

    my  ($RGB_name)         = grep( /rgb\.mnc$/i,           @entries);
    my  ($QCed_name)        = grep( /QCed\.mnc$/i,          @entries);
    my  ($XMLReport_name)   = grep( /XMLQCResult\.xml$/i,   @entries);
    my  ($QCReport_name)    = grep( /QCReport\.txt$/i,      @entries);
    
    my  $RGB        =   $DTIPrep_subdir."/".$RGB_name;
    my  $QCed       =   $DTIPrep_subdir."/".$QCed_name;
    my  $XMLReport  =   $DTIPrep_subdir."/".$XMLReport_name;
    my  $QCReport   =   $DTIPrep_subdir."/".$QCReport_name;

    return  ($QCReport,$XMLReport,$RGB,$QCed);
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
    $src        =~  s/(_QCReport\.txt|_XMLQCResult\.xml|_QCed\.mnc|_QCed_rgb\.mnc)$//;
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
    my ($minc, $registeredXMLFile, $registeredQCReportFile) = @_;

    DTI::modify_header('processing:DTIPrepTxtReport', $registeredQCReportFile, $minc) if ($registeredQCReportFile);

    DTI::modify_header('processing:DTIPrepXmlReport', $registeredXMLFile, $minc)      if ($registeredXMLFile);

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

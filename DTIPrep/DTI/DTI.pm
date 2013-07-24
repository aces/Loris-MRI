=pod

=head1 NAME

DTI --- A set of utility functions for performing common tasks relating to DTI data (particularly with regards to perform DTI QC)

=head1 SYNOPSIS

use DTI;

my $dbh = DTI::connect_to_db();

=head1 DESCRIPTION

Really a mismatch of utility functions, primarily used by DTIPrep_pipeline.pl

=head1 METHODS

=cut

package DTI;

use Exporter();
use File::Basename;
use Getopt::Tabular;
use File::Path          'make_path';
use Date::Parse;
use MNI::Startup        qw(nocputimes);
use MNI::Spawn;
use MNI::FileUtilities  qw(check_output_dirs);

@ISA        = qw(Exporter);

@EXPORT     = qw();
@EXPORT_OK  = qw(createOutputFolders getFiles sortParam insertMincHeader create_FA_RGB_maps createNoteFile);

=pod
Create DTIPrep pipeline output folders.
=cut
sub createOutputFolders{
    my  ($outdir, $subjID, $visit, $protocol) = @_;   
    
    my  $QC_out     =   $outdir . "/" .
                        $subjID . "/" .
                        $visit  . "/mri/processed/" .
                        substr(basename($protocol),0,-4);

    system("mkdir -p -m 755 $QC_out")   unless -e $QC_out;

    return  ($QC_out);
}

=pod
Function that parses files in native MRI directories and fetch only T1 structural and DTI files. This function will also concatenate together multipleDTI files if DTI acquisition performed accross several DTI scans.
=cut
sub getFiles{
    my  ($d, $QC_out, $site, $subjID, $visit, $t1_scan_type, $DTI_volumes)  =   @_;

    my  (@keep, @keep_concat, @afiles)    =   ();
    my  $anat;

    # Get all files contained in input directory without . and ..
    opendir   (DIR,"$d")   ||  die "cannot open $d\n";
    rewinddir (DIR);
    while   (my $f  =   readdir(DIR)) {
        if  ($f     =~  /\.mnc$/){
            push    (@afiles, "$d/$f"); # @afiles contains files' full path
        }
    }

    ## Grab the ones we want
    my  @DTI_frames     =   split(',',$DTI_volumes);
    my  $afiles_size    =   $#afiles;
    foreach my $f (@afiles) {
        if  (`mincinfo -dimnames $f`   =~  m/time/)    {
            my $time    =   `mincinfo -dimlength time $f`;
            chomp($time);
            if  ($time  ~~ \@DTI_frames) {
                push    (@keep, $f);
            }
        } elsif ($f    =~  m/adniT1/i) {
            $anat   =   $f;
        }
    }

    # !!!!!!!!!!! If multiple DTI needs to be concatenated. Need to test it. 
    my  $sorted         =   '';
    my  $concat;
    if  ($#DTI_frames > 0) {
        ($sorted,my $t) =   DTI::sortTimeDimension($files);
        ($concat)       =   $QC_out . "/" . $site . "_" . $subjID . "_" . $visit . "_concat.mnc";    
        my  $cmd        =   "concat-diff-header.pl @sorted $concat";
        system($cmd)    unless (-e $concat);
        push    (@keep_concat, $concat);
        return  ($anat,\@keep_concat);
    }
    
    return  ($anat,\@keep);
}


=pod
Sorts the files according to parameter specified in param 
($sort,$t) = sort_param($files, $param)
$sort = reference to array containing sorted files
$t     = list of sorted param
$files = reference to array containing name of files
$param = which attribute to sort with (ie command to pass to mincinfo without "-attvalue"
    ex: -attvalue $param where $param: acquisition:echo_time
    or $param where $param: -dimlength zspace
=cut
sub sortTimeDimension {
    my  ($files)     =   @_;

    #get param for each file
    my  %tmp    =   ();
    foreach my $f (@$files){
        my  $key    =   sprintf("%.3f", `mincinfo -dimlength time $f`);  # only keep 3 decimals 
        push    (@{$tmp{$key}},$f);
    }

    #sort in ascending order and store in a list
    my  ($sort, $t);
    foreach my $k (sort keys %tmp){
        push    (@$sort,@{$tmp{$k}});
        push    (@$t,$k); # keep sorted keys
    }

    return  ($sort,$t);
}

=pod
Function that convert minc files to nrrd, then run DTIPrep and convert the QCed files back into minc files (with updated headers). 
=cut
sub runQCtools {
    my  ($dti_file, $data_dir, $QC_out, $protocol, $DTIPrepVersion)    =   @_;

    my  ($dti_name, $nrrd, $QCed_nrrd, $QC_report, $QCed_minc, $copiedProtocol)  =   getOutputNames ($dti_file, $QC_out, $protocol);
 
    # Convert minc DTI file to nrrd 
    DTI::convert_DTI($dti_file, $nrrd, '--short --minc-to-nrrd')    unless (-e $nrrd);

    # Run DTIPrep
    if  (-e $nrrd)  {
        DTI::runDTIPrep($nrrd, $protocol, $QCed_nrrd)   unless (-e $QCed_nrrd);
        print "\n\ncp $protocol $copiedProtocol\n\n";
        system("cp $protocol $copiedProtocol")  unless (-e $copiedProtocol);
    }

    # Convert QCed nrrd file back into minc file (with updated header)
    my  $insert_header;
    if  (-e $QCed_nrrd) {
        unless (-e $QCed_minc) {
            DTI::convert_DTI($QCed_nrrd, $QCed_minc, '--nrrd-to-minc');
            ($insert_header)    =   DTI::insertMincHeader($dti_file, 
                                                          $data_dir,
                                                          $QCed_minc, 
                                                          $QC_report, 
                                                          $DTIPrepVersion);
        }
    } 

    return  ($QCed_minc,$QC_report,$insert_header);
}

=pod
=cut
sub getOutputNames {
    my  ($dti_file, $QC_out, $protocol)    =   @_;

    my $protocol_name;
    print "Protocol is: $protocol\n\n";
    if  ($protocol =~ m/XMLbcheck/i) {
        $protocol_name  =   "XMLbcheck_prot.xml";
    } elsif ($protocol =~ m/XMLnobcheck/i) {
        $protocol_name  =   "XMLnobcheck_prot.xml";
    }

    my  $dti_name       =   substr(basename($dti_file),0,-4);
    my  $nrrd           =   $QC_out . "/" . $dti_name . ".nrrd"        ;
    my  $QCed_nrrd      =   $QC_out . "/" . $dti_name . "_QCed.nrrd"   ;
    my  $QC_report      =   $QC_out . "/" . $dti_name . "_QCReport.txt";
    my  $QCed_minc      =   $QC_out . "/" . $dti_name . "_QCed.mnc"    ;
    my  $copiedProtocol =   $QC_out . "/" . $dti_name . "_" . $protocol_name ;

    return  ($dti_name, $nrrd, $QCed_nrrd, $QC_report, $QCed_minc, $copiedProtocol);
}

=pod
Function that convert minc file to nrrd or nrrd file to minc. 
(depending on $options)
=cut
sub convert_DTI {
    my  ($file_in, $file_out, $options)    =   @_;

    if  (!$options) { 
        print LOG "---DIED--- No options were define for conversion mnc2nrrd or nrrd2mnc.\n\n\n"; 
    }

    my  $cmd        =   "itk_convert $options --dwi $file_in $file_out";
    print "\n\tConverting $file_in to $file_out (...)\n$cmd\n";
    system($cmd)    unless (-e $file_out);
}

=pod
Function that run DTIPrep on nrrd file
=cut
sub runDTIPrep {
    my  ($nrrd, $protocol, $QCed_nrrd)  =   @_;    

    my  $cmd        =   "DTIPrep --DWINrrdFile $nrrd --xmlProtocol $protocol";
    print   "\n\tRunning DTIPrep (...)\n$cmd\n";
    system($cmd)    unless (-e $QCed_nrrd);
}

=pod

Insert in the minc header all the acquisition arguments except:
    - acquisition:bvalues
    - acquisition:direction_x
    - acquisition:direction_y
    - acquisition:direction_z
    - acquisition:b_matrix

Takes the raw DTI file and the QCed minc file as input and modify the QCed minc file based on the raw minc file's argument.

=cut
sub insertMincHeader {
    my  ($raw_dti, $data_dir, $processed_minc, $QC_report, $DTIPrepVersion)    =   @_;

    ### insert processing information in a mincheader field called processing:
    # 1) processing:sourceFile
    my  $sourceFile     =   $raw_dti;
    $sourceFile         =~  s/$data_dir//i;
    DTI::modify_header('processing:sourceFile', $sourceFile, $processed_minc);

    # 2) processing:sourceSeriesUID information (dicom_0x0020:el_0x000e field of $raw_dti)
    my  ($seriesUID)    =   DTI::fetch_header_info('dicom_0x0020:el_0x000e',$raw_dti,'$3, $4, $5, $6');
    DTI::modify_header('processing:sourceSeriesUID', $seriesUID, $processed_minc);

    # 3) processing:pipeline used
    DTI::modify_header('processing:pipeline', $DTIPrepVersion, $processed_minc);


#    # 1) EchoTime in the minc file
#    my  ($SourceEchoTime)   =   DTI::fetch_header_info('acquisition:echo_time',$raw_dti,'$3, $4, $5, $6');
#    DTI::modify_header('processing:sourceEchoTime', $SourceEchoTime, $QCed_minc);

    # 4) processing:processing_date (when DTIPrep was run)
    my  $check_line     =   `cat $QC_report | grep "Check Time"`;
    $check_line         =~  s/Check Time://;      # Only keep date info in $check_line.
    my ($ss,$mm,$hh,$day,$month,$year,$zone)    =   strptime($check_line);
    my $processingDate  =  sprintf("%4d%02d%02d",$year+1900,$month+1,$day);
    DTI::modify_header('processing:processing_date', $processingDate, $processed_minc);

    ### reinsert old acquisition, patient and study arguments except for the one modified by DTIPrep (i.e. acquisition:bvalues, acquisition:b_matrix and all acquisition:direction*)
    # 1) acquisition:b_value insertion
    my  ($b_value)  =   DTI::fetch_header_info('acquisition:b_value',$raw_dti,'$3, $4, $5, $6');
    DTI::modify_header('acquisition:b_value', $b_value, $processed_minc);

    # 2) acquisition:delay_in_TR insertion
    my  ($delay_in_tr)  =   DTI::fetch_header_info('acquisition:delay_in_TR',$raw_dti,'$3, $4, $5, $6');
    DTI::modify_header('acquisition:delay_in_TR', $delay_in_TR, $processed_minc);

    # 3) all the remaining acquisition:* arguments 
    #    [except acquisition:bvalues, acquisition:b_matrix and acquisition:direction* (already in header from nrrd2minc conversion)]
    my  ($acquisition_args) =   DTI::fetch_header_info('acquisition:[^dbv]',$raw_dti,'$1, $2');
    my  ($patient_args)     =   DTI::fetch_header_info('patient:',$raw_dti,'$1, $2');
    my  ($study_args)       =   DTI::fetch_header_info('study:',$raw_dti,'$1, $2');

    # fetches header info and don't remove semi_colon (last option of fetch_header_info).
    my  ($acquisition_vals) =   DTI::fetch_header_info('acquisition:[^dbv]',$raw_dti,'$3, $4, $5, $6',1);
    my  ($patient_vals)     =   DTI::fetch_header_info('patient:',$raw_dti,'$3, $4, $5, $6',1);
    my  ($study_vals)       =   DTI::fetch_header_info('study:',$raw_dti,'$3, $4, $5, $6',1);

    my  ($arguments,$values);
    if  ($processed_minc=~/(_FA\.mnc|_rgb\.mnc)$/i) {
        $arguments  =   $patient_args . $study_args;
        $values     =   $patient_vals . $study_vals;
    } elsif ($processed_minc=~/_QCed\.mnc/i) {
        $arguments  =   $acquisition_args . $patient_args . $study_args;
        $values     =   $acquisition_vals . $patient_vals . $study_vals;
    }
    my  ($arguments_list, $arguments_list_size) =   get_header_list('=', $arguments);
    my  ($values_list, $values_list_size)       =   get_header_list(';', $values);

    if  ($arguments_list_size   ==  $values_list_size)  {
        for (my $i=0;   $i<$arguments_list_size;    $i++)   {
            my  $argument   =   @$arguments_list[$i];
            my  $value      =   @$values_list[$i];
            DTI::modify_header($argument, $value, $processed_minc);
        }
        return  1;
    }else {
        return  undef;
    }
}

=pod
Function that runs minc_modify_header.
=cut
sub modify_header {
    my  ($argument, $value, $minc) =   @_;
    
    my  $cmd    =   "minc_modify_header -sinsert $argument=$value $minc";
    system($cmd);
}

=pod

=cut
sub fetch_header_info {
    my  ($field, $minc, $awk, $keep_semicolon)  =   @_;

    my  $val    =   `mincheader $minc | grep $field | awk '{print $awk}' | tr '\n' ' '`;
    my  $value  =   $val    if  $val !~ /^\s*"*\s*"*\s*$/;
    $value      =~  s/^\s+//;                           # remove leading spaces
    $value      =~  s/\s+$//;                           # remove trailing spaces
    $value      =~  s/;//   unless ($keep_semicolon);   # remove ";" unless $keep_semicolon is defined

    return  ($value);
}

=pod
Get the list of arguments and values to insert into the mincheader (acquisition:*, patient:* and study:*).
=cut
sub get_header_list {
    my  ($splitter, $fields) =   @_;
    
    my  @tmp    =   split   ($splitter, $fields);
    pop (@tmp);
    my  @items;
    foreach my $item (@tmp) { 
        $item   =~  s/^\s+//;   # remove leading spaces
        $item   =~  s/\s+$//;   # remove trailing spaces
        push    (@items, $item);
    }
    my  $list       =   \@items;
    my  $list_size  =   @$list;
    
    return  ($list, $list_size);
}

=pod
Function that created FA and RGB maps as well as the triplanar pic of the RGB map. 
=cut
sub create_FA_RGB_maps {
    my ($QCed_minc,$anat,$QC_out)   =   @_;

    my $anat_basename               =   substr(basename($anat),0,-4);
    my $QCed_minc_basename          =   substr(basename($QCed_minc),0,-4);
    my $preprocessed_minc           =   $QC_out . "/" . $anat_basename      . "-preprocessed.mnc";
    my $anat_mask                   =   $QC_out . "/" . $anat_basename      . "-n3-bet_mask.mnc";
    my $FA                          =   $QC_out . "/" . $QCed_minc_basename . "_FA.mnc";
    my $RGB                         =   $QC_out . "/" . $QCed_minc_basename . "_rgb.mnc";
    my $rgb_pic                     =   $QC_out . "/" . $QCed_minc_basename . "_RGB.png";   
    
    if  (-e $rgb_pic    &&  $RGB    &&  $anat_mask  &&  $preprocessed_minc) {
        return  0;
    }

    if  (-e $anat       &&  $QCed_minc) {
        `diff_preprocess.pl -anat $anat $QCed_minc $preprocessed_minc -outdir $QC_out`   unless (-e $preprocessed_minc);
    } else {
        return  1;
    } 

    if  (-e $anat_mask  &&  $preprocessed_minc) {
        `minctensor.pl -mask $anat_mask $preprocessed_minc -niakdir /opt/niak-0.6.4.1/ -outputdir $QC_out -octave $QCed_minc_basename`  unless (-e $FA);
    } else {
        return  2;
    }

    if  (-e $RGB)   {
        `mincpik -triplanar -horizontal $RGB $rgb_pic`  unless (-e $rgb_pic);
    } else {
        return  3;
    }
                                                                                      
    $success    =   "yes";
    return  ($success, $FA, $RGB, $rgb_pic);
}

=pod
Create a default notes file for QC summary and manual notes.
=cut
sub createNoteFile {
    my ($QC_out, $note_file, $QC_report, $reject_thresh)    =   @_;

    my ($rm_slicewise, $rm_interlace, $rm_intergradient)    =   getRejectedDirections($QC_report);

    my $count_slice     =   insertNote($note_file, $rm_slicewise,      "slicewise correlations");
    my $count_inter     =   insertNote($note_file, $rm_interlace,      "interlace correlations");
    my $count_gradient  =   insertNote($note_file, $rm_intergradient,  "gradient-wise correlations");

    my $total           =   $count_slice + $count_inter + $count_gradient;
    open    (NOTES, ">>$note_file");
    print   NOTES   "Total number of directions rejected by auto QC= $total\n";
    close   (NOTES);
    if  ($total >=  $reject_thresh) {   
        print NOTES "FAIL\n";
    } else {
        print NOTES "PASS\n";
    }

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
    my $rm_intergradient=   `cat $QCReport | sed -n -e '/Inter-gradient check Artifacts::/,/================================/p' | grep '[0-9]'| sort -k 1,1 -u  | awk '{print \$1}'|tr '\n' ','`;
    
    return ($rm_slicewise, $rm_interlace, $rm_intergradient);
}

=sub
Insert into notes file the directions rejected due to a specific artifact.
=cut
sub insertNote    {
    my ($note_file, $rm_directions, $note_field)    =   @_;

    my @rm_dirs     =   split(',',$rm_directions);
    my $count_dirs  =   scalar(@rm_dirs);

    open    (NOTES, ">>$note_file");
    print   NOTES   "Directions rejected due to $note_field: @rm_dirs ($count_dirs)\n";
    close   (NOTES);

    return  ($count_dirs);
}

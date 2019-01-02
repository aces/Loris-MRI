=pod

=head1 NAME

DTI::DTI --- A set of utility functions for performing common tasks relating to
DTI data (particularly with regards to performing DTI QC)

=head1 SYNOPSIS

  use DTI::DTI;

  my ($protXMLrefs) = &DTI::readDTIPrepXMLprot( $DTIPrepProtocol );

  my ($QCoutdir) = &DTI::createOutputFolders( $outdir,     $subjID,
                                              $visit,      $DTIPrepProtocol,
                                              $runDTIPrep
                                            );

  my ($DTIs_list)  = &DTI::getRawDTIFiles( $nativedir, $DTI_volumes );
  my ($anat)       = &DTI::getAnatFile( $nativedir, $t1_scan_type );
  my ($DTIrefs)    = &DTI::createDTIhashref( $DTIs_list,   $anat,
                                             $QCoutdir,    $DTIPrepProtocol,
                                             $protXMLrefs, $QCed2_step
                                           );

  my ($convert_status) = &DTI::convert_DTI( $dti_file,
                                            $raw_nrrd,
                                            '--short --minc-to-nrrd --dwi'
                                          );

  my ($copyProt_status) = &DTI::copyDTIPrepProtocol($DTIPrepProtocol, $QCProt);
  my ($DTIPrep_status)  = &DTI::runDTIPrep( $raw_nrrd,  $DTIPrepProtocol,
                                            $QCed_nrrd, $QCed2_nrrd
                                          );


  ($convert_status) = &DTI::convert_DTI( $QCed_nrrd,
                                         $QCed_minc,
                                         '--nrrd-to-minc --dwi'
                                       );
  ($insert_header)  = &DTI::insertMincHeader( $dti_file,      $data_dir,
                                              $QCed_minc,     $QCTxtReport,
                                              $DTIPrepVersion
                                            );


=head1 DESCRIPTION

A mishmash of utility functions, primarily used by C<DTIPrep_pipeline.pl>
and C<DTIPrepRegister.pl>.

=head2 Methods

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
@EXPORT_OK  = qw(createOutputFolders getFiles sortParam insertMincHeader create_processed_maps);


=pod

=head3 createOutputFolders($outdir, $subjID, $visit, $protocol, $runDTIPrep)

Creates DTIPrep pipeline output folders. It will return the created output
folder only if the output folder was created.

INPUTS:
  - $outdir    : base output folder
  - $subjID    : candidate ID stored in dataset's basename
  - $visit     : visit label stored in dataset's basename
  - $protocol  : DTIPrep XML protocol to use (or used) to run DTIPrep
  - $runDTIPrep: if set, will run DTIPrep and create the output dir.

Note: If C<$runDTIPrep> is not set, then DTIPrep was already run and the
output folder already exists.

RETURNS: C<candidate/visit/protocol> folder that will store DTIPrep outputs.

=cut

sub createOutputFolders{
    my  ($outdir, $subjID, $visit, $protocol, $runDTIPrep) = @_;   
    
    my  $QC_out     =   $outdir . "/" .
                        $subjID . "/" .
                        $visit  . "/mri/processed/" .
                        substr(basename($protocol),0,-4);

    system("mkdir -p -m 770 $QC_out")   unless (-e $QC_out || !$runDTIPrep);


    return  ($QC_out) if (-e $QC_out);
}


=pod

=head3 getFilesList($dir, $match)

Subroutine that will read the content of a directory and return a list
of files whose names match the string given in argument with C<$match>.

INPUTS:
  - $dir  : directory with DTI files to be fetch
  - $match: string used to look for DTI files to be returned

RETURNS: list of DTI files found in C<$dir> matching C<$match>

=cut

sub getFilesList {
    my ($dir, $match)   = @_;
    my (@files_list)    = ();

    ## Read directory $dir and stored its content in @entries 
    opendir  (DIR,"$dir")   ||  die "cannot open $dir\n";
    my @entries = readdir(DIR);
    closedir (DIR);

    ## Keep only files that match string stored in $match
    @files_list = grep(/$match/i, @entries);
    ## Add directory path to each element (file) of the array 
    @files_list = map  {"$dir/" . $_} @files_list;    

    return  (\@files_list);
}





=pod

=head3 getAnatFile($nativedir, $t1_scan_type)

Function that parses files in the native MRI directory and grabs
the T1 acquisition based on C<$t1_scan_type>.

INPUTS:
  - $nativedir   : native directory
  - $t1_scan_type: scan type string used for t1 acquisitions

RETURNS:
  - undef if no anat found
  - $anat: anatomical file (first anat found if multiple anats were found).

=cut

sub getAnatFile {
    my ($nativedir, $t1_scan_type)  = @_;

    # Fetch files in native directory that matched t1_scan_type and MINC file type
    my $anat_list = DTI::getFilesList($nativedir, "\_$t1_scan_type\_[^_]+\.mnc\$");

    # Return undef if no anat found, first anat otherwise
    return @$anat_list ? @$anat_list[0] : undef;
}


=pod

=head3 getRawDTIFiles($nativedir, $DTI_volumes)

Function that parses files in the native MRI directories and fetches DTI files.
This function will also concatenate together multiple DTI files if the DTI
acquisition was performed across several DTI scans.

INPUTS:
  - $nativedir  : native directory
  - $DTI_volumes: DTI's number of volumes

RETURNS: list of matching DTI files found in the native directory

=cut

sub getRawDTIFiles{
    my ($nativedir, $DTI_volumes)   = @_;
    
    ## Get all mincs contained in native directory
    my ($mincs_list)    = DTI::getFilesList($nativedir, 'mnc$');

    ## Grab the mincs I want, a.k.a. with minc file with $DTI_volumes 
    my @DTI_frames  = split(',',$DTI_volumes);

    # Filter the frames list: keep only the strings that are integers
    # (this should not remove anything since the $DTI_volumes string is
    # assumed to be a comma separated list of integers)
    @DTI_frames = grep($_ =~ /^\s*\d+\s*$/, @DTI_frames);
    my @DTIs_list   = (); 
    foreach my $mnc (@$mincs_list) {
        if  (`mincinfo -dimnames $mnc` =~ m/time/)    {
            my $time    = `mincinfo -dimlength time $mnc`;
            chomp($time);
            if (grep($time == $_, @DTI_frames)) {
                push (@DTIs_list, $mnc);
            }
        }
    }

    ## Return list of DTIs with the right volume numbers
    return  (\@DTIs_list);
}


=pod

=head3 copyDTIPrepProtocol($DTIPrepProtocol, $QCProt)

Function that will copy the C<DTIPrep> protocol to the output directory of
C<DTIPrep>.

INPUTS:
  - $DTIPrepProtocol: C<DTIPrep> protocol to be copied
  - $QCProt         : future path of copied C<DTIPrep> protocol

RETURNS: 1 on success, undef on failure

=cut

sub copyDTIPrepProtocol {
    my ($DTIPrepProtocol, $QCProt)    =   @_;

    my $cmd = "cp $DTIPrepProtocol $QCProt";
    system($cmd)    unless (-e $QCProt);

    if (-e $QCProt) {
        return 1;
    } else {
        return undef;
    }
}


=pod

=head3 readDTIPrepXMLprot($DTIPrepProtocol)

Read C<DTIPrep> XML protocol and return information into a hash.

INPUT: XML protocol used (or that has been used) to run C<DTIPrep>

RETURNS: reference to a hash containing C<DTIPrep> protocol as follows:

  entry   => 'QC_QCOutputDirectory'     => {}
          => 'QC_QCedDWIFileNameSuffix' => {
                                            'value'   => '_QCed.nrrd'
                                           },
          => 'IMAGE_bCheck'             => {
                   'entry' => {
                              'IMAGE_size' => {
                                               'value' => [
                                                           '96',
                                                           '96',
                                                           '65'
                                                          ]
                                              },
                              'IMAGE_reportFileMode'  => {
                                                          'value' => '1'
                                                         },
                              ...
                              'value' => 'Yes'
                              },
          => 'QC_badGradientPercentageTolerance' => {
            ...

=cut

sub readDTIPrepXMLprot {
    my ($DTIPrepProtocol)   = @_;

    my $xml             = new XML::Simple;
    my ($protXMLrefs)   = $xml->XMLin(  $DTIPrepProtocol,
                                        KeyAttr => {entry => 'parameter'},
                                        ForceArray => ['parameter']
                                     );

    return ($protXMLrefs);
}


=pod

=head3 createDTIhashref($DTIs_list, $anat, $QCoutdir, $DTIPrepProtocol, $protXMLrefs, $QCed2_step)

Function that will determine output names based on each DTI file dataset and
return a hash of DTIref:

       dti_file_1  -> Raw_nrrd     => outputname
                   -> QCed_nrrd    => outputname
                   -> QCTxtReport  => outputname
                   -> QCXmlReport  => outputname
                   -> QCed_minc    => outputname
                   -> QCProt       => outputname
       dti_file_2  -> Raw_nrrd     => outputname
        ...

INPUTS:
  - $DTIs_list      : list of native DTI files to be processed
  - $anat           : anatomical file to be used for processing
  - $QCoutdir       : processed output directory
  - $DTIPrepProtocol: C<DTIPrep> XML protocol used to run C<DTIPrep>
  - $protXMLrefs    : hash containing info about C<DTIPrep>'s protocol
  - $QCed2_step     : optionally, step name at which C<DTIPrep> will
                       produce a secondary QCed file

RETURNS: hash containing outputs naming convention

=cut

sub createDTIhashref {
    my ($DTIs_list, $anat, $QCoutdir, $DTIPrepProtocol, $protXMLrefs, $QCed2_step)    =   @_;
    my %DTIrefs;

    foreach my $dti_file (@$DTIs_list) {

        # Raw nrrd file to be processed
        my $dti_name        = substr(basename($dti_file), 0, -4);
        $DTIrefs->{$dti_file}->{'Raw'}->{'nrrd'} = $QCoutdir . "/" . $dti_name  . ".nrrd";

        # Determine preprocess outputs
        DTI::determinePreprocOutputs($QCoutdir, $dti_file, $DTIPrepProtocol, $protXMLrefs, $QCed2_step);

        # If DTI_bCompute is set to yes, DTIPrep will create FA, RGB, MD, and other output files that we will want to insert in datase
        DTI::determinePostprocOutputs($QCoutdir, $dti_file, $anat, $protXMLrefs);
            
    }
    
    return  ($DTIrefs);
}


=pod

=head3 determinePreprocOutputs($QCoutdir, $dti_file, $DTIPrepProtocol, $protXMLrefs)

Function that will determine pre processing output names (for either C<DTIPrep>
or C<mincdiffusion> postprocessing) and append them to C<$DTIrefs>.

INPUTS:
  - $QCoutdir       : directory that will contain output files
  - $dti_file       : raw DWI file to be processed
  - $DTIPrepProtocol: C<DTIPrep> protocol to copy into output directory
  - $protXMLrefs    : hash containing info from C<DTIPrep> XML protocol
                       (including suffix for the different outputs)

RETURNS: $DTIrefs{$dti_file}{'Preproc'}{'Output'} fields for C<DTIPrep>
processing

=cut

sub determinePreprocOutputs {
    my ($QCoutdir, $dti_file, $DTIPrepProtocol, $protXMLrefs, $QCed2_step)   = @_;

    my $prot_name       = basename($DTIPrepProtocol);
    my $dti_name        = substr(basename($dti_file), 0, -4);

    $DTIrefs->{$dti_file}->{'Preproc'}->{'QCProt'}->{'xml'}     = $QCoutdir . "/" . $prot_name;
    $DTIrefs->{$dti_file}->{'Preproc'}->{'QCReport'}->{'xml'}   = $QCoutdir . "/" . $dti_name  . "_XMLQCResult.xml";
    $DTIrefs->{$dti_file}->{'Preproc'}->{'QCReport'}->{'inputs'}->{'Raw_DWI'}   = $dti_file;
       
    # These are determined in DTIPrep's XML protocol 
    my $QCTxtReport = $protXMLrefs->{entry}->{QC_reportFileNameSuffix}->{value};
    my $QCed_suffix = $protXMLrefs->{entry}->{QC_QCedDWIFileNameSuffix}->{value};
    $QCed_suffix    = substr($QCed_suffix, 0, -5); # remove .nrrd from QCed suffix

    $DTIrefs->{$dti_file}->{'Preproc'}->{'QCReport'}->{'txt' }  = $QCoutdir . "/" . $dti_name  . $QCTxtReport          ;
    $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed'}->{'nrrd'}      = $QCoutdir . "/" . $dti_name  . $QCed_suffix . ".nrrd"; 
    $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed'}->{'minc'}      = $QCoutdir . "/" . $dti_name  . $QCed_suffix . ".mnc" ;

    # if a secondary QC file is written during INTERLACE_bCheck step (before motion and eddy curent corrections)
    my $QCed2_suffix= $protXMLrefs->{entry}->{INTERLACE_bCheck}->{entry}->{$QCed2_step}->{value};
    if ($QCed2_suffix) {
        $QCed2_suffix   = substr($QCed2_suffix, 0, -5); # remove .nrrd from QCed2 suffix
        $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed2'}->{'nrrd'}     = $QCoutdir . "/" . $dti_name . $QCed2_suffix . ".nrrd";
        $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed2'}->{'minc'}     = $QCoutdir . "/" . $dti_name . $QCed2_suffix . ".mnc" ;
        # {'input*'} corresponds to the files used as inputs to create the Preproc file
        $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed2'}->{'inputs'}->{'Raw_DWI'}   = $dti_file;
        $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed'}->{'inputs'}->{'QCed2'}      = $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed2'}->{'minc'};
    } else {
        $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed'}->{'inputs'}->{'Raw_DWI'}    = $dti_file;
    }
}


=pod

=head3 determinePostprocOutputs($QCoutdir, $dti_file, $anat, $protXMLrefs)

Function that will determine post processing output names (for either C<DTIPrep>
or C<mincdiffusion> postprocessing) and append them to C<$DTIrefs>.

INPUTS:
  - $QCoutdir   : directory that will contain output files
  - $dti_file   : raw DWI file to be processed
  - $anat       : T1 image to be used for C<mincdiffusion> postprocessing
  - $protXMLrefs: hash containing info from C<DTIPrep> XML protocol
                   (including suffix for the different outputs)

RETURNS:
  - $DTIrefs{$dti_file}{'Postproc'}{'Tool'} with postprocessing used
  - $DTIrefs{$dti_file}{'Postproc'}{'Output'} fields for C<DTIPrep> postprocessing

=cut

sub determinePostprocOutputs {
    my ($QCoutdir, $dti_file, $anat, $protXMLrefs) = @_;

    # Determine QCed file suffix to be used for postprocess output files
    my $QCed_suffix = $protXMLrefs->{entry}->{QC_QCedDWIFileNameSuffix}->{value};
    $QCed_suffix    = substr($QCed_suffix, 0, -5); # remove .nrrd from QCed suffix

    # Check whether DTIPrep will create FA, RGB and other postprocessing outputs (DTI_bCompute == Yes)
    my $bCompute    = $protXMLrefs->{entry}->{DTI_bCompute}->{value};

    if ($bCompute eq 'Yes') {
        
        $DTIrefs->{$dti_file}->{'Postproc'}->{'Tool'} = 'DTIPrep';
        DTI::determineDTIPrepPostprocOutputs($QCoutdir, $dti_file, $QCed_suffix, $protXMLrefs);

    } elsif ($bCompute eq 'No') {
    
        $DTIrefs->{$dti_file}->{'Postproc'}->{'Tool'} = 'mincdiffusion';
        DTI::determineMincdiffusionPostprocOutputs($QCoutdir, $dti_file, $QCed_suffix, $anat);

    }
}


=pod

=head3 determineDTIPrepPostprocOutputs($QCoutdir, $dti_file, $protXMLrefs)

Function that will determine C<DTIPrep>'s postprocessing output names (based on
the XML protocol) and append them to C<$DTIrefs>

INPUTS:
  - $QCoutdir   : directory that will contain output files
  - $dti_file   : raw DWI file to be processed
  - $protXMLrefs: hash containing info from C<DTIPrep> XML protocol

RETURNS: $DTIrefs{$dti_file}{'Postproc'}{'Output'} fields for C<DTIPrep>
postprocessing

=cut

sub determineDTIPrepPostprocOutputs {
    my ($QCoutdir, $dti_file, $QCed_suffix, $protXMLrefs) = @_;
    
    # Determine basename of the dti file to be processed
    my $dti_name        = substr(basename($dti_file), 0, -4);

    # 1. Tensor
    # Determine suffix to used for the output
    my $tensor_suffix   = $protXMLrefs->{entry}->{DTI_bCompute}->{entry}->{DTI_tensor}->{value};    
    $tensor_suffix      = $QCed_suffix . substr($tensor_suffix, 0, -5); # remove .nrrd from tensor suffix
    # Determine nrrd and minc names
    # {'input*'} corresponds to the files used as inputs to create the Preproc file
    $DTIrefs->{$dti_file}->{'Postproc'}->{'tensor'}->{'nrrd'}  = $QCoutdir . "/" . $dti_name  . $tensor_suffix . ".nrrd";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'tensor'}->{'minc'}  = $QCoutdir . "/" . $dti_name  . $tensor_suffix . ".mnc" ;

    # 2. Baseline DTI image (bvalue = 0) {value} key returns an array with 0 -> Yes/No; 1 -> output suffix to append to DTI tensor suffix
    # Determine suffix to used for the output
    my $baseline_suffix = $protXMLrefs->{entry}->{DTI_bCompute}->{entry}->{DTI_baseline}->{value}[1];    
    $baseline_suffix    = $QCed_suffix . substr($baseline_suffix, 0, -5); # remove .nrrd from baseline suffix
    $DTIrefs->{$dti_file}->{'Postproc'}->{'baseline'}->{'nrrd'}  = $QCoutdir . "/" . $dti_name  . $baseline_suffix . ".nrrd";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'baseline'}->{'minc'}  = $QCoutdir . "/" . $dti_name  . $baseline_suffix . ".mnc" ;

    # 3. RGB map {value} key returns an array with 0 -> Yes/No; 1 -> output suffix to append to DTI tensor suffix
    # Determine suffix to used for the output
    my $RGB_suffix      = $protXMLrefs->{entry}->{DTI_bCompute}->{entry}->{DTI_colorfa}->{value}[1];
    $RGB_suffix         = $tensor_suffix . substr($RGB_suffix, 0, -5); # remove .nrrd from rgb suffix
    # Determine nrrd and minc names
    $DTIrefs->{$dti_file}->{'Postproc'}->{'RGB'}->{'nrrd'}  = $QCoutdir . "/" . $dti_name  . $RGB_suffix . ".nrrd";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'RGB'}->{'minc'}  = $QCoutdir . "/" . $dti_name  . $RGB_suffix . ".mnc" ;

    # 4. FA map {value} key returns an array with 0 -> Yes/No; 1 -> output suffix to append to DTI tensor suffix
    # Determine suffix to used for the output
    my $FA_suffix       = $protXMLrefs->{entry}->{DTI_bCompute}->{entry}->{DTI_fa}->{value}[1];
    $FA_suffix          = $tensor_suffix . substr($FA_suffix, 0, -5); # remove .nrrd from FA suffix
    # Determine nrrd and minc names
    $DTIrefs->{$dti_file}->{'Postproc'}->{'FA'}->{'nrrd'}  = $QCoutdir . "/" . $dti_name  . $FA_suffix . ".nrrd";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'FA'}->{'minc'}  = $QCoutdir . "/" . $dti_name  . $FA_suffix . ".mnc" ;

    # 5. MD map {value} key returns an array with 0 -> Yes/No; 1 -> output suffix to append to DTI tensor suffix
    # Determine suffix to used for the output
    my $MD_suffix       = $protXMLrefs->{entry}->{DTI_bCompute}->{entry}->{DTI_md}->{value}[1];
    $MD_suffix          = $tensor_suffix . substr($MD_suffix, 0, -5); # remove .nrrd from MD suffix
    # Determine nrrd and minc names
    $DTIrefs->{$dti_file}->{'Postproc'}->{'MD'}->{'nrrd'}  = $QCoutdir . "/" . $dti_name  . $MD_suffix . ".nrrd";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'MD'}->{'minc'}  = $QCoutdir . "/" . $dti_name  . $MD_suffix . ".mnc" ;

    # 6. Isotropic DWI {value} key returns an array with 0 -> Yes/No; 1 -> output suffix to append to DTI tensor suffix
    # Determine suffix to used for the output
    my $IDWI_suffix     = $protXMLrefs->{entry}->{DTI_bCompute}->{entry}->{DTI_idwi}->{value}[1];
    $IDWI_suffix        = $QCed_suffix . substr($IDWI_suffix, 0, -5); # remove .nrrd from isotropic DWI suffix
    # Determine nrrd and minc names
    $DTIrefs->{$dti_file}->{'Postproc'}->{'IDWI'}->{'nrrd'}  = $QCoutdir . "/" . $dti_name  . $IDWI_suffix . ".nrrd";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'IDWI'}->{'minc'}  = $QCoutdir . "/" . $dti_name  . $IDWI_suffix . ".mnc" ;

    # Determine input files that were used to obtain the processed file
    my $QCed_minc   = $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed'}->{'minc'};
    foreach my $proc (keys ($DTIrefs->{$dti_file}->{'Postproc'})) {
        $DTIrefs->{$dti_file}->{'Postproc'}->{$proc}->{'inputs'}->{'QCed'}  = $QCed_minc;
    }
}    


=pod

=head3 determineMincdiffusionPostprocOutputs($QCoutdir, $dti_file, $QCed_suffix, $anat)

Function that will determine C<mincdiffusion> postprocessing output names and
append them to C<$DTIrefs>

INPUTS:
  - $QCoutdir   : directory that will contain output files
  - $dti_file   : raw DWI file to be processed
  - $QCed_suffix: QCed suffix for QCed NRRD & postprocessing file names
  - $anat       : anatomic T1 file to use for DWI-anat registration

RETURNS: $DTIrefs{$dti_file}{'Postproc'} for C<mincdiffusion> postprocessing

=cut

sub determineMincdiffusionPostprocOutputs {
    my ($QCoutdir, $dti_file, $QCed_suffix, $anat) = @_;
    
    # Determine basename of the dti file to be processed
    my $dti_name        = substr(basename($dti_file), 0, -4);

    # Determine basename of the anat file to be processed
    my $anat_name       = substr(basename($anat), 0, -4);

    # Determine mincdiffusion output names     
    $DTIrefs->{$dti_file}->{'Postproc'}->{'FA'}->{'minc'}               = $QCoutdir . "/" . $dti_name  . $QCed_suffix . "_FA.mnc";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'RGB'}->{'minc'}              = $QCoutdir . "/" . $dti_name  . $QCed_suffix . "_rgb.mnc";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'MD'}->{'minc'}               = $QCoutdir . "/" . $dti_name  . $QCed_suffix . "_MD.mnc";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'rgb_pic'}                    = $QCoutdir . "/" . $dti_name  . $QCed_suffix . "_RGB.png";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'baseline'}->{'minc'}         = $QCoutdir . "/" . $dti_name  . $QCed_suffix . "-frame0.mnc";
    $DTIrefs->{$dti_file}->{'Postproc'}->{'preproc'}->{'minc'}          = $QCoutdir . "/" . $dti_name . $QCed_suffix . "-preprocessed.mnc";
    $DTIrefs->{$dti_file}->{'raw_anat'}->{'minc'}                       = $anat;
    $DTIrefs->{$dti_file}->{'Postproc'}->{'anat_mask'}->{'minc'}        = $QCoutdir . "/" . $anat_name . "-n3-bet_mask.mnc";
    $DTIrefs->{$dti_file}->{'raw_anat'}->{'minc'}                       = $anat;
    $DTIrefs->{$dti_file}->{'Postproc'}->{'anat_mask_diff'}->{'minc'}   = $QCoutdir . "/" . $anat_name . "-n3-bet_mask-diffspace.mnc";

    # Determine input files of processed files
    my $QCed_minc = $DTIrefs->{$dti_file}->{'Preproc'}->{'QCed'}->{'minc'};
    foreach my $proc (keys ($DTIrefs->{$dti_file}->{'Postproc'})) {
        # All processed files had raw anat file as input
        $DTIrefs->{$dti_file}->{'Postproc'}->{$proc}->{'inputs'}->{'Raw_t1'}    = $anat;
        unless ($proc eq "anat_mask") {
            # All mincdiff processed files had $QCedminc as input except anat_mask
            $DTIrefs->{$dti_file}->{'Postproc'}->{$proc}->{'inputs'}->{'QCed'}  = $QCed_minc;
        }
    }
}    

=pod

=head3 convert_DTI($file_in, $file_out, $options)

Function that converts MINC file to NRRD or NRRD file to MINC.
(depending on C<$options>)

INPUTS:
  - $file_in : file to be converted
  - $file_out: converted file
  - $options : conversion options (C<mnc2nrrd> or C<nrrd2mnc>)

RETURNS: 1 on success, undef on failure

=cut

sub convert_DTI {
    my  ($file_in, $file_out, $options)    =   @_;

    if  (!$options) { 
        print "No options were define for conversion mnc2nrrd or nrrd2mnc.\n\n\n"; 
        return undef;
    }

    my  $cmd        =   "itk_convert $options $file_in $file_out";
    print "\n\tConverting $file_in to $file_out (...)\n$cmd\n";
    system($cmd)    unless (-e $file_out);

    if (-e $file_out) {
        return 1;   # successfully converted
    } else {
        return undef;   # failed during conversion
    }
}


=pod

=head3 runDTIPrep($raw_nrrd, $protocol, $QCed_nrrd, $QCed2_nrrd)

Function that runs C<DTIPrep> on NRRD file.

INPUTS:
  - $raw_nrrd  : raw DTI NRRD file to be processed through C<DTIPrep>
  - $protocol  : C<DTIPrep> protocol used
  - $QCed_nrrd : QCed file produced by C<DTIPrep>
  - $QCed2_nrrd: optionally, secondary QCed file

RETURNS: 1 on success, under on failure

=cut

sub runDTIPrep {
    my  ($raw_nrrd, $protocol, $QCed_nrrd, $QCed2_nrrd)  =   @_;    

    my  $cmd        =   "DTIPrep --DWINrrdFile $raw_nrrd --xmlProtocol $protocol";
    print   "\n\tRunning DTIPrep (...)\n$cmd\n";
    system($cmd)    unless (-e $QCed_nrrd);

    if (($QCed2_nrrd) && ((-e $QCed_nrrd) && (-e $QCed2_nrrd))) {
        return 1;
    } elsif ((!$QCed2_nrrd) && (-e $QCed_nrrd)) {
        return 1;
    } else {
        return undef;
    }
}


=pod

=head3 insertMincHeader($raw_file, $data_dir, $processed_minc, $QC_report, $DTIPrepVersion, $is_anat)

Inserts in the MINC header all the acquisition arguments except:
  - acquisition:bvalues
  - acquisition:direction_x
  - acquisition:direction_y
  - acquisition:direction_z
  - acquisition:b_matrix

Takes the raw DTI file and the QCed MINC file as input and modifies
the QCed MINC file based on the raw MINC file's argument.

If one of the value to insert is not defined, return undef, otherwise return 1.

INPUTS:
  - $raw_file      : raw DTI MINC file to grep header information
  - $data_dir      : data dir as defined in the profile file
  - $processed_minc: processed MINC file in which to insert header information
  - $QC_report     : C<DTIPrep> QC report text file
  - $DTIPrepVersion: C<DTIPrep> version used to obtain processed file
  - $is_anat       : if set, will only insert processing, patient & study info

RETURNS: 1 on success, undef on failure

=cut

sub insertMincHeader {
    my  ($raw_file, $data_dir, $processed_minc, $QC_report, $DTIPrepVersion, $is_anat)    =   @_;

    # insertion of processed information into $processed_minc
    my ($procInsert)    =   DTI::insertProcessInfo($raw_file, $data_dir, $processed_minc, $QC_report, $DTIPrepVersion);

    # insert old acquisition, patient and study arguments except for the one modified by DTIPrep (i.e. acquisition:bvalues, acquisition:b_matrix and all acquisition:direction*) unless $is_anat is set (raw_file is anat file)
    my  ($acqInsert)    =   DTI::insertAcqInfo($raw_file, $processed_minc) unless ($is_anat);

    # insert patient information from the raw dataset into the processed files
    my  ($patientInsert)=   DTI::insertFieldList($raw_file, $processed_minc, 'patient:');

    # insert study information from the raw dataset into the processed files
    my  ($studyInsert)  =   DTI::insertFieldList($raw_file, $processed_minc, 'study:');

    if (($procInsert) && (($acqInsert)||($is_anat)) && ($patientInsert) && ($studyInsert)) {
        return 1;
    } else {
        return undef;
    }
}


=pod

=head3 insertProcessInfo($raw_dti, $data_dir, $processed_minc, ...)

This will insert in the header of the processed file processing information. If
one of the value to insert is not defined, return undef, otherwise return 1.

INPUTS:
  - $raw_dti       : raw DTI MINC file to grep header information from
  - $data_dir      : data dir as defined in the profile file
  - $processed_minc: processed MINC file in which to insert header info
  - $QC_report     : C<DTIPrep> QC report text file
  - $DTIPrepVersion: C<DTIPrep> version used to obtain processed file

RETURNS: 1 on success, undef on failure

=cut

sub insertProcessInfo {
    my ($raw_dti, $data_dir, $processed_minc, $QC_report, $DTIPrepVersion) = @_;

    # 1) processing:sourceFile
    my  $sourceFile         =   $raw_dti;
    $sourceFile             =~  s/$data_dir//i;
    my ($sourceFile_insert) = &DTI::modify_header('processing:sourceFile', $sourceFile, $processed_minc, '$3, $4, $5, $6');

    # 2) processing:sourceSeriesUID information (dicom_0x0020:el_0x000e field of $raw_dti)
    my  ($seriesUID)        = &DTI::fetch_header_info('dicom_0x0020:el_0x000e',$raw_dti,'$3, $4, $5, $6');
    my ($seriesUID_insert)  = &DTI::modify_header('processing:sourceSeriesUID', $seriesUID, $processed_minc, '$3, $4, $5, $6');

    # 3) processing:pipeline used
    my ($pipeline_insert)   = &DTI::modify_header('processing:pipeline', 'DTIPrepPipeline', $processed_minc, '$3, $4, $5, $6');
    
    # 4) processing:tool used
    my ($tool_insert)       = &DTI::modify_header('processing:tool', $DTIPrepVersion, $processed_minc, '$3, $4, $5, $6');

    # 5) processing:processing_date (when DTIPrep was run)
    my  $check_line         =   `cat $QC_report | grep "Check Time"`;
    $check_line             =~  s/Check Time://;  # Only keep date info in $check_line.
    my ($ss,$mm,$hh,$day,$month,$year,$zone)    =   strptime($check_line);
    my $processingDate      =   sprintf("%4d%02d%02d",$year+1900,$month+1,$day);
    my ($date_insert)       = &DTI::modify_header('processing:processing_date', $processingDate, $processed_minc, '$3, $4, $5, $6');

    if (($sourceFile_insert) 
     && ($seriesUID_insert) 
     && ($pipeline_insert) 
     && ($tool_insert) 
     && ($date_insert)) {
        return 1;
    } else {
        return undef;
    }
}


=pod

=head3 insertAcqInfo($raw_dti, $processed_minc)

Inserts acquisition information extracted from raw DTI dataset and insert it in
the processed file. If one of the value to insert is not defined, return
undef, otherwise return 1.

INPUTS:
  - $raw_dti       : raw DTI MINC file to grep header information
  - $processed_minc: processed MINC file in which to insert header info

RETURNS: 1 on success, undef on failure

=cut

sub insertAcqInfo {
    my  ($raw_dti, $processed_minc) = @_;

    # 1) insertion of acquisition:b_value 
    my ($b_value)       = DTI::fetch_header_info('acquisition:b_value',$raw_dti,'$3, $4, $5, $6');
    my ($bvalue_insert) = DTI::modify_header('acquisition:b_value', $b_value, $processed_minc, '$3, $4, $5, $6');

    # 2) insertion of acquisition:delay_in_TR 
    my ($delay_in_tr)   = DTI::fetch_header_info('acquisition:delay_in_TR',$raw_dti,'$3, $4, $5, $6');
    my ($delaytr_insert)= DTI::modify_header('acquisition:delay_in_TR', $delay_in_tr, $processed_minc, '$3, $4, $5, $6');

    # 3) insertion of all the remaining acquisition:* arguments 
    #    [except acquisition:bvalues, acquisition:b_matrix and acquisition:direction* (already in header from nrrd2minc conversion)]
    my  ($acqInsert)    =   DTI::insertFieldList($raw_dti, $processed_minc, 'acquisition:[^dbv]');   

    if  (($bvalue_insert) && ($delaytr_insert) && ($acqInsert)) {
        return 1;
    } else {
        return undef;
    }
}


=pod

=head3 insertFieldList($raw_dti, $processed_minc, $minc_field)

Inserts information extracted from raw DTI dataset and insert it in the
processed file. If one of the value to insert is not defined, return undef,
otherwise return 1.

INPUTS:
  - $raw_dti       : raw DTI MINC file to grep header information from
  - $processed_minc: processed MINC file in which to insert header info
  - $minc_field    : MINC field to be inserted in processed MINC file

RETURNS: 1 on success, undef on failure

=cut

sub insertFieldList {
    my  ($raw_dti, $processed_minc, $minc_field) = @_;

    # fetches list of arguments starting with $minc_field (i.e. 'patient:'; 'study:' ...)
    my  ($arguments) =   DTI::fetch_header_info($minc_field, $raw_dti, '$1, $2');

    # fetches list of values with arguments starting with $minc_field. Don't remove semi_colon (last option of fetch_header_info).
    my  ($values) =   DTI::fetch_header_info($minc_field, $raw_dti, '$3, $4, $5, $6, $7', 1);

    my  ($arguments_list, $arguments_list_size) =   get_header_list('=', $arguments);
    my  ($values_list, $values_list_size)       =   get_header_list(';', $values);

    my  @insert_failure;
    if  ($arguments_list_size   ==  $values_list_size)  {
        for (my $i=0;   $i<$arguments_list_size;    $i++)   {
            my  $argument   =   @$arguments_list[$i];
            my  $value      =   @$values_list[$i];
            my ($insert)    = DTI::modify_header($argument, $value, $processed_minc, '$3, $4, $5, $6');
            # store in array @insert_failure the arguments that were not successfully inserted in the mincheader
            push (@insert_failure, $argument) if (!$insert);
        }
        # if at least one insertion failed, will return undef, otherwise 1.
        if ($#insert_failure >= 0) {
            return  undef;
        } else {
            return 1;
        }
    # if arguments_list and values_list do not have the same size, will return undef    
    }else {
        return  undef;
    }
}    


=pod

=head3 modify_header($argument, $value, $minc, $awk)

Function that runs C<minc_modify_header> and inserts MINC header information if
not already inserted.

INPUTS:
  - $argument: argument to be inserted in MINC header
  - $value   : value of the argument to be inserted in MINC header
  - $minc    : MINC file
  - $awk     : awk info to check if the argument was inserted in MINC header

RETURNS: 1 if argument was inserted in the MINC header, undef otherwise

=cut

sub modify_header {
    my  ($argument, $value, $minc, $awk) =   @_;
    
    # check if header information not already in minc file
    my $hdr_val =   &DTI::fetch_header_info($argument, $minc, $awk);

    # insert mincheader unless mincheader field already inserted ($hdr_val eq $value)
    my  $cmd    =   "minc_modify_header -sinsert $argument=$value $minc";
    system($cmd)    unless (($hdr_val) && ($value eq $hdr_val));

    # check if header information was indeed inserted in minc file
    my $hdr_val2 =   &DTI::fetch_header_info($argument, $minc, $awk);
    if ($hdr_val2) {
        return 1;
    } else {
        return undef;
    }
}


=pod

=head3 fetch_header_info($field, $minc, $awk, $keep_semicolon)

Function that fetches header information in MINC file.

INPUTS:
  - $field: field to look for in MINC header
  - $minc : MINC file
  - $awk  : awk info to check if argument inserted in MINC header
  - $keep_semicolon: if set, keep ";" at the end of extracted value

RETURNS: value of the field found in the MINC header

=cut

sub fetch_header_info {
    my  ($field, $minc, $awk, $keep_semicolon)  =   @_;

    my  $val    =   `mincheader $minc | grep $field | awk '{print $awk}' | tr '\n' ' '`;
    my  $value  =   $val    if  $val !~ /^\s*"*\s*"*\s*$/;
    if ($value) {
        $value  =~  s/^\s+//;                           # remove leading spaces
        $value  =~  s/\s+$//;                           # remove trailing spaces
        $value  =~  s/;//   unless ($keep_semicolon);   # remove ";" unless $keep_semicolon is defined
    } else {
        return undef;
    }

    return  ($value);
}


=pod

=head3 get_header_list($splitter, $fields)

Gets the list of arguments and values to insert into the MINC header
(C<acquisition:*>, C<patient:*> and C<study:*>).

INPUTS:
  - $splitter: delimiter used to split list of fields stored in C<$fields>
  - $fields  : list header arguments/values to insert in the MINC header

RETURNS: - $list     : array of header arguments and values' list
         - $list_size: size of the array $list

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

=head3 mincdiff_preprocess($dti_file, $DTIrefs, $QCoutdir)

Function that runs C<diff_preprocess.pl> script from the C<mincdiffusion>
tools on the QCed MINC and raw anat dataset.

INPUTS:
  - $dti_file: hash key to use to fetch file names (e.g. raw DWI file)
  - $DTIrefs : hash storing file names to be used
  - $QCoutdir: directory used to create outputs from QC pipeline

RETURNS: 1 on success, undef on failure

=cut

sub mincdiff_preprocess {
    my ($dti_file, $DTIrefs, $QCoutdir) = @_;    
    
    # Initialize variables
        # 1. input data
    my $QCed_minc     = $DTIrefs->{$dti_file}{'Preproc'}{'QCed'}{'minc'};
    my $QCed_basename = substr(basename($QCed_minc),0,-4);
    my $raw_anat      = $DTIrefs->{$dti_file}{'raw_anat'}{'minc'};
        # 2. output data
    my $preproc_minc  = $DTIrefs->{$dti_file}{'Postproc'}{'preproc'}{'minc'};
    my $baseline      = $DTIrefs->{$dti_file}{'Postproc'}{'baseline'}{'minc'};
    my $anat_mask     = $DTIrefs->{$dti_file}{'Postproc'}{'anat_mask'}{'minc'};

    # Run diff_preprocess.pl script 
    `diff_preprocess.pl -anat $raw_anat $QCed_minc $preproc_minc -outdir $QCoutdir`;

    # Check that all output files were created
    if ((-e $preproc_minc) && (-e $anat_mask) && (-e $baseline)) {
        $DTIrefs->{$dti_file}{'mincdiff_preproc_status'}    = "success";
        return 1;
    } else {
        $DTIrefs->{$dti_file}{'mincdiff_preproc_status'}    = "failed";
        return undef;
    }
}


=pod

=head3 mincdiff_minctensor($dti_file, $DTIrefs, $QCoutdir, $niak_path)

Function that runs C<minctensor.pl> script from the C<mincdiffusion> tools on
the C<mincdiff> preprocessed MINC and anatomical mask images.

INPUTS:
  - $dti_file: hash key to use to fetch file names (e.g. raw DWI file)
  - $DTIrefs : hash storing file names to be used
  - $QCoutdir: directory used to create outputs from QC pipeline

RETURNS: 1 on success, undef on failure

=cut

sub mincdiff_minctensor {
    my ($dti_file, $DTIrefs, $QCoutdir, $niak_path) = @_;

    # Initialize variables
        # 1. input data
    my $QCed_minc     = $DTIrefs->{$dti_file}{'Preproc'}{'QCed'}{'minc'};
    my $QCed_basename = substr(basename($QCed_minc), 0, -4);
    my $preproc_minc  = $DTIrefs->{$dti_file}{'Postproc'}{'preproc'}{'minc'};
    my $anat_mask     = $DTIrefs->{$dti_file}{'Postproc'}{'anat_mask'}{'minc'};
        # 2. output data
    my $FA            = $DTIrefs->{$dti_file}{'Postproc'}{'FA'}{'minc'};
    my $MD            = $DTIrefs->{$dti_file}{'Postproc'}{'MD'}{'minc'};
    my $RGB           = $DTIrefs->{$dti_file}{'Postproc'}{'RGB'}{'minc'};
    my $anat_mask_diff= $DTIrefs->{$dti_file}{'Postproc'}{'anat_mask_diff'}{'minc'};

    # Change directory to make sure outputs 

    # Run minctensor.pl script  
    `minctensor.pl -mask $anat_mask $preproc_minc -niakdir $niak_path -outputdir $QCoutdir -octave $QCoutdir/$QCed_basename`;

    # Check that all output files were created
    if ((-e $FA) && (-e $RGB) && (-e $MD) && (-e $anat_mask_diff)) {
        $DTIrefs->{$dti_file}{'minctensor_status'}  = "success";
        return 1;
    } else {
        $DTIrefs->{$dti_file}{'minctensor_status'}  = "failed";
        return undef;
    }
}


=pod

=head3 RGBpik_creation($dti_file, $DTIrefs)

Function that runs C<mincpik> on the RGB map.

INPUTS:
  - $dti_file: hash key to use to fetch file names (e.g. raw DWI file)
  - $DTIrefs : hash storing file names to be used

RETURNS: 1 on success, undef on failure

=cut

sub RGBpik_creation {
    my ($dti_file, $DTIrefs) = @_;

    # Initialize variables
        # 1. input file
    my $RGB     = $DTIrefs->{$dti_file}{'Postproc'}{'RGB'}{'minc'};
        # 2. output file
    my $rgb_pic = $DTIrefs->{$dti_file}{'Postproc'}{'rgb_pic'};   

    # Run mincpik on the RGB map
    `mincpik -triplanar -horizontal $RGB $rgb_pic`;

    # Check that the RGB pik was created
    if (-e $rgb_pic) {
        return 1;
    } else {
        return undef;
    }
}


=pod

=head3 convert_DTIPrep_postproc_outputs($dti_file, $DTIrefs, $data_dir, $DTIPrepVersion)

This function will check if all C<DTIPrep> NRRD files were created and convert
them into MINC files with relevant header information inserted.

INPUTS:
  - $dti_file      : raw DTI dataset that was processed through C<DTIPrep>
  - $DTIrefs       : hash containing information about output names
  - $data_dir      : directory containing raw DTI dataset
  - $DTIPrepVersion: C<DTIPrep> version used to process the DWI dataset

RETURNS:
  - $nrrds_found  : 1 if all NRRD outputs found, undef otherwise
  - $mincs_created: 1 if all NRRD files converted to MINC files,
                      undef otherwise
  - $hdrs_inserted: 1 if all header info inserted in MINC files,
                      undef otherwise

=cut

sub convert_DTIPrep_postproc_outputs {
    my ($dti_file, $DTIrefs, $data_dir, $QCTxtReport, $DTIPrepVersion) = @_;

    # 1. Initialize variables
    my $tensor_nrrd     = $DTIrefs->{$dti_file}->{'Postproc'}->{'tensor'}->{'nrrd'};
    my $tensor_minc     = $DTIrefs->{$dti_file}->{'Postproc'}->{'tensor'}->{'minc'};
    my $baseline_nrrd   = $DTIrefs->{$dti_file}->{'Postproc'}->{'baseline'}->{'nrrd'};
    my $baseline_minc   = $DTIrefs->{$dti_file}->{'Postproc'}->{'baseline'}->{'minc'};
    my $rgb_nrrd        = $DTIrefs->{$dti_file}->{'Postproc'}->{'RGB'}->{'nrrd'};
    my $rgb_minc        = $DTIrefs->{$dti_file}->{'Postproc'}->{'RGB'}->{'minc'};
    my $fa_nrrd         = $DTIrefs->{$dti_file}->{'Postproc'}->{'FA'}->{'nrrd'};
    my $fa_minc         = $DTIrefs->{$dti_file}->{'Postproc'}->{'FA'}->{'minc'};
    my $md_nrrd         = $DTIrefs->{$dti_file}->{'Postproc'}->{'MD'}->{'nrrd'};
    my $md_minc         = $DTIrefs->{$dti_file}->{'Postproc'}->{'MD'}->{'minc'};
    my $idwi_nrrd       = $DTIrefs->{$dti_file}->{'Postproc'}->{'IDWI'}->{'nrrd'};
    my $idwi_minc       = $DTIrefs->{$dti_file}->{'Postproc'}->{'IDWI'}->{'minc'};

    # 2. Check that all processed outputs were created
    my $nrrds_found;
    if ((-e $tensor_nrrd) && (-e $baseline_nrrd) && (-e $rgb_nrrd) && (-e $fa_nrrd) && (-e $md_nrrd) && (-e $idwi_nrrd)) {
        $nrrds_found = 1;
    } else {
        $nrrds_found = undef;
    }

    # 3. Check if minc processed files were already created and create them
    my ($mincs_created, $hdrs_inserted);
    if ((-e $tensor_minc) && (-e $baseline_minc) && (-e $rgb_minc) && (-e $fa_minc) && (-e $md_minc) && (-e $idwi_minc)) {
        $mincs_created   = 1;
    } else {
        # convert processed files
        my ($tensor_convert_status)  = DTI::convert_DTI($tensor_nrrd,   $tensor_minc,   '--nrrd-to-minc --dti');
        my ($baseline_convert_status)= DTI::convert_DTI($baseline_nrrd, $baseline_minc, '--nrrd-to-minc');
        my ($rgb_convert_status)     = DTI::convert_DTI($rgb_nrrd,      $rgb_minc,      '--nrrd-to-minc');
        my ($fa_convert_status)      = DTI::convert_DTI($fa_nrrd,       $fa_minc,       '--nrrd-to-minc');
        my ($md_convert_status)      = DTI::convert_DTI($md_nrrd,       $md_minc,       '--nrrd-to-minc');
        my ($idwi_convert_status)    = DTI::convert_DTI($idwi_nrrd,     $idwi_minc,     '--nrrd-to-minc');
        $mincs_created  = 1     if (($tensor_convert_status) && ($baseline_convert_status) && ($rgb_convert_status) && ($fa_convert_status) && ($md_convert_status) && ($idwi_convert_status));
    }

    # 4. insert mincheader information stored in raw DWI dataset (except fields with direction informations)
    my ($tensor_insert_status)   = DTI::insertMincHeader($dti_file, $data_dir, $tensor_minc,    $QCTxtReport, $DTIPrepVersion);
    my ($baseline_insert_status) = DTI::insertMincHeader($dti_file, $data_dir, $baseline_minc,  $QCTxtReport, $DTIPrepVersion);
    my ($rgb_insert_status)      = DTI::insertMincHeader($dti_file, $data_dir, $rgb_minc,       $QCTxtReport, $DTIPrepVersion);
    my ($fa_insert_status)       = DTI::insertMincHeader($dti_file, $data_dir, $fa_minc,        $QCTxtReport, $DTIPrepVersion);
    my ($md_insert_status)       = DTI::insertMincHeader($dti_file, $data_dir, $md_minc,        $QCTxtReport, $DTIPrepVersion);
    my ($idwi_insert_status)     = DTI::insertMincHeader($dti_file, $data_dir, $idwi_minc,      $QCTxtReport, $DTIPrepVersion);
    $hdrs_inserted  = 1     if (($tensor_insert_status) && ($baseline_insert_status) && ($rgb_insert_status) && ($fa_insert_status) && ($md_insert_status) && ($idwi_insert_status));

    # 5. Return statements
    return ($nrrds_found, $mincs_created, $hdrs_inserted);

}

=pod

=head3 getRejectedDirections($data_dir, $XMLReport)

Summarize which directions were rejected by C<DTIPrep> for slice-wise
correlations,
inter-lace artifacts, inter-gradient artifacts.

INPUTS:
  - $data_dir: data_dir defined in the config file
  - $QCReport: C<DTIPrep>'s QC txt report to extract rejected directions

RETURNS: 
  - number of directions rejected due to slice wise correlations
  - number of directions rejected due to interlace artifacts
  - number of directions rejected due to inter-gradient artifacts

=cut

sub getRejectedDirections   {
    my ($data_dir, $XMLReport)  =   @_;

    # Remove $data_dir path from $QCReport in the case it is included in the path
    $XMLReport =~ s/$data_dir//i;

    # Read XML report into a hash
    my ($outXMLrefs)    = &DTI::readDTIPrepXMLprot("$data_dir/$XMLReport");

    # Initialize variables
    my ($tot_grads, $slice_excl, $grads_excl, $lace_excl, $tot_excl);
    $tot_grads  = $slice_excl = $grads_excl = $lace_excl = $tot_excl = 0;
    my (@rm_slice, @rm_interlace, @rm_intergrads);

    foreach my $key (keys $outXMLrefs->{"entry"}{"DWI Check"}{'entry'}) {
        # Next unless this is a gradient
        next unless ($key =~ /^gradient_/);

        # Grep gradient number
        my $grad_nb = $key;
        $grad_nb    =~ s/gradient_[0]+//i;

         # Grep processing status for the gradient
        my $status  = $outXMLrefs->{"entry"}{"DWI Check"}{'entry'}{$key}{'processing'};

        # Count number of gradients with different exclusion status
        if ($status =~ /EXCLUDE_SLICECHECK/i) {
            $slice_excl = $slice_excl + 1;
            push (@rm_slice, $grad_nb);
            $tot_excl   = $tot_excl + 1;
        } elsif ($status =~ /EXCLUDE_GRADIENTCHECK/i) {
            $grads_excl = $grads_excl + 1;
            push (@rm_intergrads, $grad_nb);
            $tot_excl   = $tot_excl + 1;
        } elsif ($status =~ /EXCLUDE_INTERLACECHECK/i) {
            $lace_excl  = $lace_excl + 1;
            push (@rm_interlace, $grad_nb);
            $tot_excl   = $tot_excl + 1;
        }
        $tot_grads  = $tot_grads + 1;
    }

    # Summary hash storing all DTIPrep gradient exclusion information
    my (%summary);
    # Total number of gradients in native DTI
    $summary{'total'}{'nb'}                  = $tot_grads;
    # Total number of gradients excluded from QCed DTI
    $summary{'EXCLUDED'}{'total'}{'nb'}      = $tot_excl;
    # Total number of gradients included in QCed DTI
    $summary{'INCLUDED'}{'total'}{'nb'}      = $tot_grads - $tot_excl;
    # Summary of artifact exclusions
    $summary{'EXCLUDED'}{'slice'}{'nb'}      = $slice_excl;
    $summary{'EXCLUDED'}{'slice'}{'txt'}     = "\'Directions "
                                                    . join(',', @rm_slice)
                                                    . "(" . $slice_excl . ")\'";
    $summary{'EXCLUDED'}{'intergrad'}{'nb'}  = $grads_excl;
    $summary{'EXCLUDED'}{'intergrad'}{'txt'} = "\'Directions "
                                                    . join(',', @rm_intergrads)
                                                    . "(" . $grads_excl . ")\'";
    $summary{'EXCLUDED'}{'interlace'}{'nb'}  = $lace_excl;
    $summary{'EXCLUDED'}{'interlace'}{'txt'} = "\'Directions "
                                                    . join(',', @rm_interlace)
                                                    . "(" . $lace_excl . ")\'";

    return (\%summary);
}

1;

__END__


=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut



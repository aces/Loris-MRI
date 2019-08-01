# NAME

DTI::DTI --- A set of utility functions for performing common tasks relating to
DTI data (particularly with regards to performing DTI QC)

# SYNOPSIS

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

# DESCRIPTION

A mishmash of utility functions, primarily used by `DTIPrep_pipeline.pl`
and `DTIPrepRegister.pl`.

## Methods

### createOutputFolders($outdir, $subjID, $visit, $protocol, $runDTIPrep)

Creates DTIPrep pipeline output folders. It will return the created output
folder only if the output folder was created.

INPUTS:
  - $outdir    : base output folder
  - $subjID    : candidate ID stored in dataset's basename
  - $visit     : visit label stored in dataset's basename
  - $protocol  : DTIPrep XML protocol to use (or used) to run DTIPrep
  - $runDTIPrep: if set, will run DTIPrep and create the output dir.

Note: If `$runDTIPrep` is not set, then DTIPrep was already run and the
output folder already exists.

RETURNS: `candidate/visit/protocol` folder that will store DTIPrep outputs.

### getFilesList($dir, $match)

Subroutine that will read the content of a directory and return a list
of files whose names match the string given in argument with `$match`.

INPUTS:
  - $dir  : directory with DTI files to be fetch
  - $match: string used to look for DTI files to be returned

RETURNS: list of DTI files found in `$dir` matching `$match`

### getAnatFile($nativedir, $t1\_scan\_type)

Function that parses files in the native MRI directory and grabs
the T1 acquisition based on `$t1_scan_type`.

INPUTS:
  - $nativedir   : native directory
  - $t1\_scan\_type: scan type string used for t1 acquisitions

RETURNS:
  - undef if no anat found
  - $anat: anatomical file (first anat found if multiple anats were found).

### getRawDTIFiles($nativedir, $DTI\_volumes)

Function that parses files in the native MRI directories and fetches DTI files.
This function will also concatenate together multiple DTI files if the DTI
acquisition was performed across several DTI scans.

INPUTS:
  - $nativedir  : native directory
  - $DTI\_volumes: DTI's number of volumes

RETURNS: list of matching DTI files found in the native directory

### copyDTIPrepProtocol($DTIPrepProtocol, $QCProt)

Function that will copy the `DTIPrep` protocol to the output directory of
`DTIPrep`.

INPUTS:
  - $DTIPrepProtocol: `DTIPrep` protocol to be copied
  - $QCProt         : future path of copied `DTIPrep` protocol

RETURNS: 1 on success, undef on failure

### readDTIPrepXMLprot($DTIPrepProtocol)

Read `DTIPrep` XML protocol and return information into a hash.

INPUT: XML protocol used (or that has been used) to run `DTIPrep`

RETURNS: reference to a hash containing `DTIPrep` protocol as follows:

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

### createDTIhashref($DTIs\_list, $anat, $QCoutdir, $DTIPrepProtocol, $protXMLrefs, $QCed2\_step)

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
  - $DTIs\_list      : list of native DTI files to be processed
  - $anat           : anatomical file to be used for processing
  - $QCoutdir       : processed output directory
  - $DTIPrepProtocol: `DTIPrep` XML protocol used to run `DTIPrep`
  - $protXMLrefs    : hash containing info about `DTIPrep`'s protocol
  - $QCed2\_step     : optionally, step name at which `DTIPrep` will
                       produce a secondary QCed file

RETURNS: hash containing outputs naming convention

### determinePreprocOutputs($QCoutdir, $dti\_file, $DTIPrepProtocol, $protXMLrefs)

Function that will determine pre processing output names (for either `DTIPrep`
or `mincdiffusion` postprocessing) and append them to `$DTIrefs`.

INPUTS:
  - $QCoutdir       : directory that will contain output files
  - $dti\_file       : raw DWI file to be processed
  - $DTIPrepProtocol: `DTIPrep` protocol to copy into output directory
  - $protXMLrefs    : hash containing info from `DTIPrep` XML protocol
                       (including suffix for the different outputs)

RETURNS: $DTIrefs{$dti\_file}{'Preproc'}{'Output'} fields for `DTIPrep`
processing

### determinePostprocOutputs($QCoutdir, $dti\_file, $anat, $protXMLrefs)

Function that will determine post processing output names (for either `DTIPrep`
or `mincdiffusion` postprocessing) and append them to `$DTIrefs`.

INPUTS:
  - $QCoutdir   : directory that will contain output files
  - $dti\_file   : raw DWI file to be processed
  - $anat       : T1 image to be used for `mincdiffusion` postprocessing
  - $protXMLrefs: hash containing info from `DTIPrep` XML protocol
                   (including suffix for the different outputs)

RETURNS:
  - $DTIrefs{$dti\_file}{'Postproc'}{'Tool'} with postprocessing used
  - $DTIrefs{$dti\_file}{'Postproc'}{'Output'} fields for `DTIPrep` postprocessing

### determineDTIPrepPostprocOutputs($QCoutdir, $dti\_file, $protXMLrefs)

Function that will determine `DTIPrep`'s postprocessing output names (based on
the XML protocol) and append them to `$DTIrefs`

INPUTS:
  - $QCoutdir   : directory that will contain output files
  - $dti\_file   : raw DWI file to be processed
  - $protXMLrefs: hash containing info from `DTIPrep` XML protocol

RETURNS: $DTIrefs{$dti\_file}{'Postproc'}{'Output'} fields for `DTIPrep`
postprocessing

### determineMincdiffusionPostprocOutputs($QCoutdir, $dti\_file, $QCed\_suffix, $anat)

Function that will determine `mincdiffusion` postprocessing output names and
append them to `$DTIrefs`

INPUTS:
  - $QCoutdir   : directory that will contain output files
  - $dti\_file   : raw DWI file to be processed
  - $QCed\_suffix: QCed suffix for QCed NRRD & postprocessing file names
  - $anat       : anatomic T1 file to use for DWI-anat registration

RETURNS: $DTIrefs{$dti\_file}{'Postproc'} for `mincdiffusion` postprocessing

### convert\_DTI($file\_in, $file\_out, $options)

Function that converts MINC file to NRRD or NRRD file to MINC.
(depending on `$options`)

INPUTS:
  - $file\_in : file to be converted
  - $file\_out: converted file
  - $options : conversion options (`mnc2nrrd` or `nrrd2mnc`)

RETURNS: 1 on success, undef on failure

### runDTIPrep($raw\_nrrd, $protocol, $QCed\_nrrd, $QCed2\_nrrd)

Function that runs `DTIPrep` on NRRD file.

INPUTS:
  - $raw\_nrrd  : raw DTI NRRD file to be processed through `DTIPrep`
  - $protocol  : `DTIPrep` protocol used
  - $QCed\_nrrd : QCed file produced by `DTIPrep`
  - $QCed2\_nrrd: optionally, secondary QCed file

RETURNS: 1 on success, under on failure

### insertMincHeader($raw\_file, $data\_dir, $processed\_minc, $QC\_report, $DTIPrepVersion, $is\_anat)

Inserts in the MINC header all the acquisition arguments except:
  - acquisition:bvalues
  - acquisition:direction\_x
  - acquisition:direction\_y
  - acquisition:direction\_z
  - acquisition:b\_matrix

Takes the raw DTI file and the QCed MINC file as input and modifies
the QCed MINC file based on the raw MINC file's argument.

If one of the value to insert is not defined, return undef, otherwise return 1.

INPUTS:
  - $raw\_file      : raw DTI MINC file to grep header information
  - $data\_dir      : data dir as defined in the profile file
  - $processed\_minc: processed MINC file in which to insert header information
  - $QC\_report     : `DTIPrep` QC report text file
  - $DTIPrepVersion: `DTIPrep` version used to obtain processed file
  - $is\_anat       : if set, will only insert processing, patient & study info

RETURNS: 1 on success, undef on failure

### insertProcessInfo($raw\_dti, $data\_dir, $processed\_minc, ...)

This will insert in the header of the processed file processing information. If
one of the value to insert is not defined, return undef, otherwise return 1.

INPUTS:
  - $raw\_dti       : raw DTI MINC file to grep header information from
  - $data\_dir      : data dir as defined in the profile file
  - $processed\_minc: processed MINC file in which to insert header info
  - $QC\_report     : `DTIPrep` QC report text file
  - $DTIPrepVersion: `DTIPrep` version used to obtain processed file

RETURNS: 1 on success, undef on failure

### insertAcqInfo($raw\_dti, $processed\_minc)

Inserts acquisition information extracted from raw DTI dataset and insert it in
the processed file. If one of the value to insert is not defined, return
undef, otherwise return 1.

INPUTS:
  - $raw\_dti       : raw DTI MINC file to grep header information
  - $processed\_minc: processed MINC file in which to insert header info

RETURNS: 1 on success, undef on failure

### insertFieldList($raw\_dti, $processed\_minc, $minc\_field)

Inserts information extracted from raw DTI dataset and insert it in the
processed file. If one of the value to insert is not defined, return undef,
otherwise return 1.

INPUTS:
  - $raw\_dti       : raw DTI MINC file to grep header information from
  - $processed\_minc: processed MINC file in which to insert header info
  - $minc\_field    : MINC field to be inserted in processed MINC file

RETURNS: 1 on success, undef on failure

### modify\_header($argument, $value, $minc)

Function that runs `minc_modify_header` and inserts MINC header information if
not already inserted.

INPUTS:
  - $argument: argument to be inserted in MINC header
  - $value   : value of the argument to be inserted in MINC header
  - $minc    : MINC file

RETURNS: 1 if argument was inserted in the MINC header, undef otherwise

### get\_header\_list($splitter, $fields)

Gets the list of arguments and values to insert into the MINC header
(`acquisition:*`, `patient:*` and `study:*`).

INPUTS:
  - $splitter: delimiter used to split list of fields stored in `$fields`
  - $fields  : list header arguments/values to insert in the MINC header

RETURNS: - $list     : array of header arguments and values' list
         - $list\_size: size of the array $list

### mincdiff\_preprocess($dti\_file, $DTIrefs, $QCoutdir)

Function that runs `diff_preprocess.pl` script from the `mincdiffusion`
tools on the QCed MINC and raw anat dataset.

INPUTS:
  - $dti\_file: hash key to use to fetch file names (e.g. raw DWI file)
  - $DTIrefs : hash storing file names to be used
  - $QCoutdir: directory used to create outputs from QC pipeline

RETURNS: 1 on success, undef on failure

### mincdiff\_minctensor($dti\_file, $DTIrefs, $QCoutdir, $niak\_path)

Function that runs `minctensor.pl` script from the `mincdiffusion` tools on
the `mincdiff` preprocessed MINC and anatomical mask images.

INPUTS:
  - $dti\_file: hash key to use to fetch file names (e.g. raw DWI file)
  - $DTIrefs : hash storing file names to be used
  - $QCoutdir: directory used to create outputs from QC pipeline

RETURNS: 1 on success, undef on failure

### RGBpik\_creation($dti\_file, $DTIrefs)

Function that runs `mincpik.pl` on the RGB map.

INPUTS:
  - $dti\_file: hash key to use to fetch file names (e.g. raw DWI file)
  - $DTIrefs : hash storing file names to be used

RETURNS: 1 on success, undef on failure

### convert\_DTIPrep\_postproc\_outputs($dti\_file, $DTIrefs, $data\_dir, $DTIPrepVersion)

This function will check if all `DTIPrep` NRRD files were created and convert
them into MINC files with relevant header information inserted.

INPUTS:
  - $dti\_file      : raw DTI dataset that was processed through `DTIPrep`
  - $DTIrefs       : hash containing information about output names
  - $data\_dir      : directory containing raw DTI dataset
  - $DTIPrepVersion: `DTIPrep` version used to process the DWI dataset

RETURNS:
  - $nrrds\_found  : 1 if all NRRD outputs found, undef otherwise
  - $mincs\_created: 1 if all NRRD files converted to MINC files,
                      undef otherwise
  - $hdrs\_inserted: 1 if all header info inserted in MINC files,
                      undef otherwise

### getRejectedDirections($data\_dir, $XMLReport)

Summarize which directions were rejected by `DTIPrep` for slice-wise
correlations,
inter-lace artifacts, inter-gradient artifacts.

INPUTS:
  - $data\_dir: data\_dir defined in the config file
  - $QCReport: `DTIPrep`'s QC txt report to extract rejected directions

RETURNS: 
  - number of directions rejected due to slice wise correlations
  - number of directions rejected due to interlace artifacts
  - number of directions rejected due to inter-gradient artifacts

# LICENSING

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

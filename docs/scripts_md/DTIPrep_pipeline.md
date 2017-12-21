# NAME

DTIPrep\_pipeline.pl -- Run DTIPrep and/or insert DTIPrep's outputs in the
database.

# SYNOPSIS

perl DTIPrep\_pipeline.pl -profile `prod` -list
`/path/to/list/of/native/dir` -DTIPrepVersion `DTIPrep_version`
\-mincdiffusionVersion `mincdiffusion_version` -runDTIPrep - DTIPrepProtocol
`/path/to/DTIPrep/XML/protocol` -registerFilesInDB

Note:
\- `-DTIPrepVersion` and `-mincdiffusionVersion` are optional if the
version of those tools can be found directly from the tools installed on the
server running `DTIPrepRegister`.
\- `-runDTIPrep` and `registerFilesInDB` are optional depending on whether
just want to run the DTIPrep pipeline or just want to register the outputs...

# DESCRIPTION

`DTIPrep_pipeline.pl` can be used to run DTIPrep on native DWI datasets. It
will also organize, convert and register the outputs of DTIPrep in the database.

If `-runDTIPrep` option is not set, DTIPrep processing will be skipped
(DTIPrep outputs being already available, as well as the DTIPrep protocol that
was used).

This pipeline will:
  - grep native DWI files from list of given native directories (-list option)
  - create (or fetch if `-runDTIPrep` not set) output directories based on the
     DTIPrep version and protocol that are to be (or were) used for DTIPrep
     processing.
  - convert native DWI minc file to NRRD & run DTIPrep if `-runDTIPrep` is set
  - fetch DTIPrep preprocessing outputs (QCed.nrrd, QCReport.txt,
     QCXMLResults.xml and protocol.xml)
  - convert pre-processed NRRD back to MINC with all the header information
     (based on the native MINC file)
  - create post-processing files (FA, RGB maps...) with all header information
  - call `DTIPrepRegister.pl` to register the files in the database if
     `-registerFilesInDB` is set

## Methods

### identify\_tool\_version($tool, $match)

Function that determines the tool version used for processing.

INPUT: tool to search absolute path containing version information, string to
match to determine tool version

RETURNS: version of the tool found, or undef if version could not be
determined based on the path

### getIdentifiers($nativedir)

Fetches CandID and visit label from the native directory of the dataset to
process. Relevant information will also be printed in the log file.

INPUT: native directory of the dataset to process

RETURNS: $candID & $visit\_label information, or undef if could not find the
site, CandID or visit label.

### getOutputDirectories($outdir, $subjID, $visit, $DTIPrepProtocol, ...)

Determine pipeline's output directory, based on the root `$outdir`, DTIPrep
protocol, candID and visit label: (outdir/ProtocolName/CandID/VisitLabel).
  - If $runDTIPrep is defined, the function will create the output folders.
  - If $runDTIPrep is not defined, will check that the directory exists.

INPUT:
  - $outdir         : root directory for DTIPrep outputs (in
                       `/data/project/data/pipelines/DTIPrep/DTIPrep_version`)
  - $subjID         : candidate ID of the DTI dataset to be processed
  - $visit          : visit label of the DTI dataset to be processed
  - $DTIPrepProtocol: XML file with the DTIPrep protocol to be used for analyses
  - $runDTIPrep     : boolean, if OutputFolders should be created in the
                       filesystem (before processing data through DTIPrep) if
                       they don't exist

RETURNS: directory where processed files for the candidate, visit label and
DTIPrep protocol will be stored.

### fetchData($nativedir, $DTI\_volumes, $t1\_scan\_type, $QCoutdir, ...)

Fetch the raw DWI datasets and foreach DWI, determine output names to be used
and store them into a hash ($DTIrefs). Will also print relevant information
in the log file.

INPUT:
  - $nativedir      : native directory to look for native DWI dataset
  - $DTI\_volumes    : number of volumes expected in the DWI dataset
  - $t1\_scan\_type   : the scan type name of the T1 weighted dataset
  - $QCoutdir       : directory to save processed files
  - $DTIPrepProtocol: XML DTIPrep protocol to be used to process DWI datasets

RETURNS:
  - list of raw DTIs found, a hash with the preprocessing output names
     and paths if raw DWI dataset was found.
  - undef if could not find any raw DWI dataset.

### preprocessingPipeline($DTIs\_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol)

Function that creates the output folders, get the raw DTI files, convert them
to NRRD and run DTIPrep using a `bcheck` protocol and a `nobcheck` protocol.

INPUT:
  - $DTIs\_list      : list of DWI files to process for a given candidate/visit
  - $DTIrefs        : hash with output file names & paths for the different DWI
  - $QCoutdir       : output directory to use to save preprocessed files.
  - $DTIPrepProtocol: XML DTIPrep protocol to use to pre-process the DWI data

RETURNS:
  - 1 if at least one raw DWI dataset was successfully preprocessed
  - undef if pre-processing was not successful on a least one raw DWI dataset

### preproc\_mnc2nrrd($raw\_nrrd, $dti\_file)

Function that convert MINC raw DWI file to NRRD and log the conversion status.

INPUT: raw NRRD file to create, raw DWI file to convert to NRRD

RETURNS: 1 on success, undef on failure

### preproc\_DTIPrep($QCed\_nrrd, $raw\_nrrd, $DTIPrepProtocol, $QCed2\_nrrd)

This function will call `&DTI::runDTIPrep` to run DTIPrep on the raw NRRD file.

INPUT:
  - $QCed\_nrrd      : QCed DWI NRRD file to be created by DTIPrep
  - $raw\_nrrd       : raw DWI NRRD file to process through DTIPrep
  - $DTIPrepProtocol: DTIPrep XML Protocol to use to run DTIPrep

RETURNS: 1 on success, undef on failure

### preproc\_copyXMLprotocol($QCProt, $QCoutdir, $DTIPrepProtocol)

Function that will call `&DTI::copyDTIPrepProtocol` if the XML protocol has
not already been copied in DTIPrep QC outdir.

INPUT:
  - $QCProt         : copied QC XML protocol (in QC output folder)
  - $QCoutdir       : QC output directory
  - $DTIPrepProtocol: DTIPrep XML protocol used to run DTIPrep

RETURNS: 1 on success, undef on failure

### check\_and\_convertPreprocessedFiles($DTIs\_list, $DTIrefs, $data\_dir, ...)

This function will check pre-processing outputs and call
`&convertPreproc2mnc`, which will convert and reinsert headers into MINC file.

INPUT:
  - $DTIs\_list      : list of raw DWI that were pre-processed
  - $DTIrefs        : hash with list of raw DTIs as a key & corresponding
                       output names as values
  - $data\_dir       : directory containing raw DWI dataset
  - $QCoutdir       : directory containing preprocessed outputs
  - $DTIPrepProtocol: DTIPrep XML protocol used to run DTIPrep
  - $DTIPrepVersion : DTIPrep version that was run to preprocess images

Output: - Will return undef if could not find preprocessed files or convert it to minc.
        - Will return 1 if conversion was a success and all preprocessing files were found in QC outdir.

### checkPreprocessOutputs($dti\_file, $DTIrefs, $QCoutdir, $DTIPrepProtocol)

Check if all pre-processing DTIPrep files are in the output folder. They
should include:
  - QCed NRRD file
  - DTIPrep QC text report
  - DTIPrep QC XML report
  - a copy of the protocol used to run DTIPrep
Relevant information will also be printed in the log file.

INPUT:
  - $dti\_file       : raw DWI file that was processed
  - $DTIrefs        : hash containing output names
  - $QCoutdir       : preprocessing output directory
  - $DTIPrepProtocol: DTIPrep XML protocol that was used to run DTIPrep

RETURNS: 1 if all output files were found, undef if at least one output file
is missing

### convertPreproc2mnc($dti\_file, $DTIrefs, $data\_dir, $DTIPrepVersion)

This function will convert to MINC DTI QCed NRRD file from DTIPrep and reinsert
all mincheader information.

INPUT:
  - $dti\_file      : raw DWI file to be processed
  - $DTIrefs       : hash containing output names
  - $data\_dir      : directory containing the raw dataset
  - $DTIPrepVersion: DTIPrep version used to pre-process raw DWI

RETURNS: 1 if QCed MINC file created and exists; undef otherwise

### mincdiffusionPipeline($DTIs\_list, $DTIrefs, $data\_dir, $QCoutdir, ...)

Running post-processing pipeline that will check if post-processing outputs
already exist. If they don't exist, it will call `&runMincdiffusion` to run
the mincdiffusion tools.

INPUT:
  - $DTIs\_list      : list with raw DWI to post-process
  - $DTIrefs        : hash containing output names and paths
  - $data\_dir       : directory hosting raw DWI dataset
  - $QCoutdir       : QC process output directory
  - $DTIPrepProtocol: DTIPrep XML protocol used to run DTIPrep
  - $mincdiffVersion: mincdiffusion version

RETURNS: 1 if all post-processing outputs found, undef otherwise

### checkMincdiffusionPostProcessedOutputs($dti\_file, $DTIrefs, $QCoutdir)

Function that check if all outputs are present in the QC output directory.

INPUT:
  - $dti\_file: raw DWI dataset to use as a key in $DTIrefs
  - $DTIrefs : hash containing output names
  - $QCoutdir: QC output directory

RETURNS: 1 if all post processing outputs were found, undef otherwise

### runMincdiffusionTools($dti\_file, $DTIrefs, $data\_dir, $QCoutdir, ...)

Will create FA, MD and RGB maps.

INPUT:
  - $dti\_file       : raw DWI file that is used as a key in $DTIrefs
  - $DTIrefs        : hash containing output names and paths
  - $data\_dir       : directory containing raw datasets
  - $QCoutdir       : QC output directory
  - $mincdiffVersion: mincdiffusion version used

RETURNS: 1 on success, undef on failure

### check\_and\_convert\_DTIPrep\_postproc\_outputs($DTIs\_list, $DTIrefs, ...)

Function that loop through DTI files acquired for the CandID and session to
check if DTIPrep post processed NRRD files have been created and convert them
to MINC files with relevant header information.

INPUT:
  - $DTIs\_list     : list of DTI files for the session and candidate
  - $DTIrefs       : hash containing references for all DTI output naming
  - $data\_dir      : directory containing the raw DTI dataset
  - $QCoutdir      : directory containing the processed data
  - $DTIPrepVersion: Version of DTIPrep used to process the data

RETURNS: 1 on success, undef on failure

### register\_processed\_files\_in\_DB($DTIs\_list, $DTIrefs, $profile, ...)

Calls the script `DTIPrepRegister.pl` to register processed files into the
database.

INPUT:
  - $DTIs\_list      : list of native DTI files processed
  - $DTIrefs        : hash containing the processed filenames
  - $profile        : config file (a.k.a ./dicom-archive/.loris\_mri/prod)
  - $QCoutdir       : output directory containing the processed files
  - $DTIPrepVersion : DTIPrep version used to obtain QCed files
  - $mincdiffVersion: mincdiffusion tool version used

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

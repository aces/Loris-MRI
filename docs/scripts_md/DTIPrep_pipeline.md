# NAME

DTIPrep\_pipeline.pl -- Run `DTIPrep` and/or insert `DTIPrep`'s outputs in the
database.

# SYNOPSIS

perl DTIPrep\_pipeline.p `[options]`

\-profile             : name of config file in
                        `../dicom-archive/.loris_mri`

\-list                : file containing the list of raw diffusion MINC
                        files (in `assembly/DCCID/Visit/mri/native`)

\-DTIPrepVersion      : `DTIPrep` version used (if cannot be found in
                        `DTIPrep` binary path)

\-mincdiffusionVersion: `mincdiffusion` release version used (if cannot be
                        found in `mincdiffusion` scripts path)

\-runDTIPrep          : if set, run `DTIPrep` on the raw MINC DTI data

\-DTIPrepProtocol     : `DTIPrep` protocol to use (or used) to run `DTIPrep`

\-registerFilesInDB   : if set, registers outputs file in the database

**Notes:**

\- tool version options (`-DTIPrepVersion` & `-mincdiffusionVersion`)
do not need to be set if they can be found directly in the path of the binary
tools.

\- the script can be run without the `-runDTIPrep` option if execution of
`DTIPrep` is not needed.

\- the script can be run without the `-registerFilesInDB` option if
registration of `DTIPrep` is not needed.

# DESCRIPTION

`DTIPrep_pipeline.pl` can be used to run `DTIPrep` on native DWI datasets. It
will also organize, convert and register the outputs of `DTIPrep` in the
database.

If `-runDTIPrep` option is not set, `DTIPrep` processing will be skipped
(`DTIPrep` outputs being already available, as well as the `DTIPrep` protocol
that was used).

**This pipeline will:**

1) grep native DWI files from list of given native directories (`-list` option)

2) create (or fetch if `-runDTIPrep` not set) output directories based
   on the `DTIPrep` version and protocol that are to be (or were) used
   for `DTIPrep` processing

3) convert native DWI MINC file to NRRD and run `DTIPrep` if `-runDTIPrep`
   option is set

4) fetch `DTIPrep` pre-processing outputs (QCed.nrrd, QCReport.txt,
   QCXMLResults.xml & protocol.xml)

5) convert pre-processed NRRD files back to MINC with all the header
   information (based on the native MINC file)

6) create post-processing files (FA, RGB maps...) with all the header
   information

7) call `DTIPrepRegister.pl` to register the files in the database if
     `-registerFilesInDB` is set

## Methods

### identify\_tool\_version($tool, $match)

Function that determines the tool version used for processing.

INPUTS:
  - $tool : tool to search absolute path containing version information
  - $match: string to match to determine tool version

RETURNS: version of the tool found, or undef if version could not be
determined based on the path

### getIdentifiers($nativedir)

Fetches `CandID` and visit label from the native directory of the dataset to
process. Relevant information will also be printed in the log file.

INPUT: native directory of the dataset to process

RETURNS: undef if could not determine the site, `CandID`, visit OR
  - $candID     : candidate DCCID
  - $visit\_label: visit label

### getOutputDirectories($outdir, $subjID, $visit, $DTIPrepProtocol, $runDTIPrep)

Determine pipeline's output directory based on the root `$outdir`, `DTIPrep`
protocol name, candidate ID `CandID` and visit label:
`outdir/ProtocolName/CandID/VisitLabel`

\- If `$runDTIPrep` is set, the function will create the output folders

\- If `$runDTIPrep` is not set, the function will check that the directory exists

INPUTS:
  - $outdir         : root directory for `DTIPrep` outputs (in
                       `/data/$PROJECT/data/pipelines/DTIPrep/DTIPrep_version`)
  - $subjID         : candidate ID of the DTI dataset to be processed
  - $visit          : visit label of the DTI dataset to be processed
  - $DTIPrepProtocol: XML file with the `DTIPrep` protocol to use
  - $runDTIPrep     : boolean, if output folders should be created in
                       the filesystem (before processing data through
                       `DTIPrep`) if they don't exist

RETURNS: directory where processed files for the candidate, visit label and
DTIPrep protocol will be stored.

### fetchData($nativedir, $DTI\_volumes, $t1\_scan\_type, $QCoutdir, $DTIPrepProtocol)

Fetches the raw DWI datasets and foreach DWI, determines output names to be used
and stores them into a hash (`$DTIrefs`). Will also print relevant information
in the log file.

INPUTS:
  - $nativedir      : native directory to look for native DWI dataset
  - $DTI\_volumes    : number of volumes expected in the DWI dataset
  - $t1\_scan\_type   : the scan type name of the T1 weighted dataset
  - $QCoutdir       : directory to save processed files
  - $DTIPrepProtocol: XML `DTIPrep` protocol to use

RETURNS: undef if could not find any raw DWI dataset OR
  - $DTIs\_list: list of raw DTIs found
  - $DTIrefs  : a hash with the pre-processing output names and paths

### preprocessingPipeline($DTIs\_list, $DTIrefs, $QCoutdir, $DTIPrepProtocol)

Function that creates the output folders, gets the raw DTI files, converts them
to NRRD and runs `DTIPrep` using a `bcheck` protocol and a `nobcheck` protocol.

INPUTS:
  - $DTIs\_list      : list of DWI files to process for a given `CandID/Visit`
  - $DTIrefs        : hash with output file names & paths for the
                       different DWI to process
  - $QCoutdir       : output directory to save preprocessed files
  - $DTIPrepProtocol: XML `DTIPrep` protocol to use for pre-processing

RETURNS:
  - 1 if at least one raw DWI dataset was successfully preprocessed
  - undef if pre-processing was not successful on a least one raw DWI dataset

### preproc\_mnc2nrrd($raw\_nrrd, $dti\_file)

Function that converts MINC raw DWI file to NRRD and logs the conversion status.

INPUTS:
  - $raw\_nrrd: raw NRRD file to create
  - $dti\_file: raw DWI file to convert to NRRD

RETURNS: 1 on success, undef on failure

### preproc\_DTIPrep($QCed\_nrrd, $raw\_nrrd, $DTIPrepProtocol, $QCed2\_nrrd)

This function will call `&DTI::runDTIPrep` to run `DTIPrep` on the raw NRRD file.

INPUTS:
  - $QCed\_nrrd      : QCed DWI NRRD file to be created by `DTIPrep`
  - $raw\_nrrd       : raw DWI NRRD file to process through `DTIPrep`
  - $DTIPrepProtocol: `DTIPrep` XML Protocol to use to run `DTIPrep`

RETURNS: 1 on success, undef on failure

### preproc\_copyXMLprotocol($QCProt, $QCoutdir, $DTIPrepProtocol)

Function that will call `&DTI::copyDTIPrepProtocol` if the XML protocol has
not already been copied in `DTIPrep` QC directory.

INPUTS:
  - $QCProt         : copied QC XML protocol (in QC output folder)
  - $QCoutdir       : QC output directory
  - $DTIPrepProtocol: `DTIPrep` XML protocol used to run `DTIPrep`

RETURNS: 1 on success, undef on failure

### check\_and\_convertPreprocessedFiles($DTIs\_list, $DTIrefs, $data\_dir, $QCoutdir, $DTIPrepProtocol, $DTIPrepVersion)

This function will check pre-processing outputs and call
`&convertPreproc2mnc`, which will convert and reinsert headers into MINC file.

INPUTS:
  - $DTIs\_list      : list of raw DWI that were pre-processed
  - $DTIrefs        : hash with list of raw DTIs as a key &
                       corresponding output names as values
  - $data\_dir       : directory containing raw DWI dataset
  - $QCoutdir       : directory containing preprocessed outputs
  - $DTIPrepProtocol: `DTIPrep` XML protocol used to run `DTIPrep`
  - $DTIPrepVersion : `DTIPrep` version that was run to pre-process images

RETURNS:
  - undef if could not find pre-processed files or convert them to MINC
  - 1 if successful conversion & all pre-processing files found in the QC directory

### checkPreprocessOutputs($dti\_file, $DTIrefs, $QCoutdir, $DTIPrepProtocol)

Checks if all pre-processing `DTIPrep` files are in the output folder. They
should include:
  - QCed NRRD file
  - `DTIPrep` QC text report
  - `DTIPrep` QC XML report
  - a copy of the protocol used to run `DTIPrep`

Relevant information will also be printed in the log file.

INPUTS:
  - $dti\_file       : raw DWI file that was processed
  - $DTIrefs        : hash containing output names
  - $QCoutdir       : pre-processing output directory
  - $DTIPrepProtocol: `DTIPrep` XML protocol that was used to run `DTIPrep`

RETURNS: undef if at least one output file is missing; 1 if all output files
were found

### convertPreproc2mnc($dti\_file, $DTIrefs, $data\_dir, $DTIPrepVersion)

This function will convert to MINC DTI QCed NRRD file from `DTIPrep` and reinsert
all MINC header information.

INPUTS:
  - $dti\_file      : raw DWI file to be processed
  - $DTIrefs       : hash containing output names
  - $data\_dir      : directory containing the raw dataset
  - $DTIPrepVersion: `DTIPrep` version used to pre-process raw DWI

RETURNS: 1 if QCed MINC file created and exists; undef otherwise

### mincdiffusionPipeline($DTIs\_list, $DTIrefs, $data\_dir, $QCoutdir, ...)

Running post-processing pipeline that will check if post-processing outputs
already exist. If they don't exist, it will call `&runMincdiffusion` to run
the `mincdiffusion` tools.

INPUTS:
  - $DTIs\_list      : list with raw DWI to post-process
  - $DTIrefs        : hash containing output names and paths
  - $data\_dir       : directory hosting raw DWI dataset
  - $QCoutdir       : QC process output directory
  - $DTIPrepProtocol: `DTIPrep` XML protocol used to run `DTIPrep`
  - $mincdiffVersion: `mincdiffusion` version

RETURNS: 1 if all post-processing outputs found, undef otherwise

### checkMincdiffusionPostProcessedOutputs($dti\_file, $DTIrefs, $QCoutdir)

Function that checks if all outputs are present in the QC output directory.

INPUTS:
  - $dti\_file: raw DWI dataset to use as a key in `$DTIrefs`
  - $DTIrefs : hash containing output names
  - $QCoutdir: QC output directory

RETURNS: 1 if all post processing outputs were found, undef otherwise

### runMincdiffusionTools($dti\_file, $DTIrefs, $data\_dir, $QCoutdir, $mincdiffVersion)

Will create FA, MD and RGB maps.

INPUTS:
  - $dti\_file       : raw DWI file that is used as a key in `$DTIrefs`
  - $DTIrefs        : hash containing output names and paths
  - $data\_dir       : directory containing raw datasets
  - $QCoutdir       : QC output directory
  - $mincdiffVersion: `mincdiffusion` version used

RETURNS: 1 on success, undef on failure

### check\_and\_convert\_DTIPrep\_postproc\_outputs($DTIs\_list, $DTIrefs, $data\_dir, $QCoutdir, $DTIPrepVersion)

Function that loops through DTI files acquired for the `CandID` and session to
check if `DTIPrep` post processed NRRD files have been created and converts them
to MINC files with relevant header information.

INPUTS:
  - $DTIs\_list     : list of DTI files for the session and candidate
  - $DTIrefs       : hash containing references for DTI output naming
  - $data\_dir      : directory containing the raw DTI dataset
  - $QCoutdir      : directory containing the processed data
  - $DTIPrepVersion: version of `DTIPrep` used to process the data

RETURNS: 1 on success, undef on failure

### register\_processed\_files\_in\_DB($DTIs\_list, $DTIrefs, $profile, $QCoutdir, $DTIPrepVersion, $mincdiffVersion)

Calls the script `DTIPrepRegister.pl` to register processed files into the
database.

INPUT:
  - $DTIs\_list      : list of native DTI files processed
  - $DTIrefs        : hash containing the processed filenames
  - $profile        : config file (in `../dicom-archive/.loris_mri`)
  - $QCoutdir       : output directory containing the processed files
  - $DTIPrepVersion : `DTIPrep` version used to obtain QCed files
  - $mincdiffVersion: `mincdiffusion` tool version used

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

# NAME

DTIPrepRegister.pl -- registers DTIPrep outputs in the LORIS database

# SYNOPSIS

perl DTIPrepRegister.pl `[options]`

Available options are:

\-profile        : name of the config file in ../dicom-archive/.loris-mri

\-DTIPrep\_subdir : DTIPrep subdirectory storing the processed files to
                   be registered

\-DTIPrepProtocol: DTIPrep protocol used to obtain the output files

\-DTI\_file       : native DWI file used to obtain the output files

\-anat\_file      : native anatomical dataset used to create FA, RGB and
                   other post-processed maps using mincdiffusion tools

\-DTIPrepVersion : DTIPrep version used if it cannot be found in MINC
                   files' `processing:pipeline` header field

\-mincdiffusionVersion: mincdiffusion release version used if it cannot be
                        found in minc files' `processing:pipeline`
                        header field

Note: `-DTIPrepVersion` and `-mincdiffusionVersion` are optional if the
version of those tools can be found directly in the MINC header of the
processed files.

# DESCRIPTION

Registers DWI QC pipeline's output files of interest into the LORIS database
via `register_processed_data.pl`.

The following output files will be inserted:
  - QCed MINC file produced by DTIPrep pre-processing step (i.e. DWI
     dataset without the bad directions detected by DTIPrep)
  - QCReport produced by DTPrep
  - XMLQCResult produced by DTIPrep
  - RGB map produced by either DTIPrep or mincdiffusion post-processing
  - MD map produced by either DTIPrep or mincdiffusion post-processing
  - FA map produced by either DTIPrep or mincdiffusion post-processing
  - baseline image produced by DTIPrep or mincdiffusion post-processing
  - DTI mask produced by mincdiffusion post-processing (only if
     mincdiffusion was used to post-process the data)

## Methods

### register\_XMLProt($XMLProtocol, $data\_dir, $tool)

Registers XML protocol file into the `mri_processing_protocol` table. It will
first check if protocol file was already registered in the database. If the
protocol file is already registered in the database, it will return the
ProcessProtocolID from the database. If the protocol file is not registered yet
in the database, it will register it in the database and return the
ProcessProtocolID of the registered protocol file.

INPUTS:
  - $XMLProtocol: XML protocol file of DTIPrep to be registered
  - $data\_dir   : data directory from the `Config` table, tool name of the
                   protocol (a.k.a. "DTIPrep")

RETURNS: ID of the registered protocol file

### registerProtocol($protocol, $md5sum, $tool, $data\_dir)

Registers protocol file into `mri_processing_protocol` table and move the
protocol to the `$data_dir/protocols/DTIPrep` folder.

INPUTS:
  - $protocol: protocol file to be registered
  - $md5sum  : md5sum of the protocol file to be registered
  - $tool    : tool of the protocol file (DTIPrep)
  - $data\_dir: data\_dir of the prod file

RETURNS: ID of the registered protocol file

### fetchProtocolID($md5sum)

Fetches the protocol ID in the `mri_processing_protocol` table based on
the XML protocol's md5sum.

INPUT: md5sum of the XML protocol

RETURNS: ID of the registered protocol file

### register\_minc($minc, $raw\_file, $data\_dir, $inputs, ...)

Sets the different parameters needed for MINC files' registration
and calls `&registerFile` to register the MINC file in the database
via `register_processed_data.pl` script.

INPUTS:
  - $minc                  : MINC file to be registered
  - $raw\_file              : source file of the MINC file to register
  - $data\_dir              : data\_dir directory from the config table
  - $inputs                : input files of the file to be registered
  - $pipelineName          : name of the pipeline used to obtain the
                              MINC file
  - $toolName              : tool name & version used
  - $registeredXMLFile     : registered DTIPrep XML report
  - $registeredQCReportFile: registered DTIPrep txt report
  - $scanType              : scan type of the MINC file to register
  - $registered\_nrrd       : optional, registered NRRD file used to
                              create the MINC file

RETURNS: registered MINC file on success, undef otherwise

### register\_XMLFile($XMLFile, $raw\_file, $data\_dir, $QCReport, ...)

Sets parameters needed to register the XML report/protocol of DTIPrep
and calls registerFile to register the XML file via register\_processed\_data.pl.

INPUT:
  - $XMLFile     : XML file to be registered
  - $raw\_file    : native DWI file used to obtain the DTIPrep outputs
  - $data\_dir    : data\_dir from the config table
                    (e.g. /data/project/data)
  - $QCReport    : DTIPrep QCreport
  - $inputs      : input files used to process data through DTIPrep
  - $pipelineName: pipeline name used to process DWIs (DTIPrepPipeline)
  - $toolName    : DTIPrep name & version used to process the DWI file

RETURNS: the registered XNL file if it was registered in the database, undef
          otherwise

### register\_QCReport($QCReport, $raw\_file, $data\_dir, $inputs, ...)

Sets parameters needed to register the QCreport of DTIPrep and calls
`&registerFile` to register the QCreport file via
`register_processed_data.pl`.

INPUTS:
  - $QCReport    : QC report file to be registered
  - $raw\_file    : native DWI file used to obtain the DTIPrep outputs
  - $data\_dir    : data\_dir from the config table
                    (e.g. /data/project/data)
  - $inputs      : input files used to process data through DTIPrep
  - $pipelineName: pipeline name used to process DTIs (DTIPrepPipeline)
  - $toolName    : DTIPrep name & version used to process the DWI file

RETURNS: registered QCReport file if it was registered in the database, undef
          otherwise

### getFiles($dti\_file, $DTIrefs)

This function checks that all the processing files exist on the filesystem and
returns the files to be inserted in the database. When NRRD and MINC files are
found, it will only return the MINC file. (NRRD files will be linked to the
MINC file when inserting files in the database).

INPUTS:
  - $dit\_file: raw DTI dataset that is used as a key in `$DTIrefs` hash
  - $DTIref  : hash containing all output paths and tool information

RETURNS:
  - $XMLProtocol    : DTIPrep XML protocol found in the file system
  - $QCReport       : DTIPrep text QCReport found in the file system
  - $XMLReport      : DTIPrep XML QCReport found in the file system
  - $QCed\_minc      : QCed MINC file created after conversion of
                       QCed NRRD file
  - $RGB\_minc       : RGB MINC file found in the file system
  - $FA\_minc        : FA MINC file found in the file system
  - $MD\_minc        : MD MINC file found in the file system
  - $baseline\_minc  : baseline MINC file found in the file system
  - $brain\_mask\_minc: brain mask MINC file found in the file system
  - $QCed2\_minc     : optional, secondary QCed MINC file created after
                       conversion of secondary QCed DTIPrep NRRD file
  - returns undef if there are some missing files (except for
     QCed2\_minc which is optional)

### checkPreprocessFiles($dti\_file, $DTIrefs, $mri\_files)

Function that checks if all DTIPrep pre-processing files are present in the
file system.

INPUTS:
  - $dti\_file: raw DTI dataset that is used as a key in $DTIrefs hash
  - DTIrefs  : hash containing all output paths and tool information
  - mri\_files: list of processed outputs to register or that have been
                registered

RETURNS:
  - $XMLProtocol: DTIPrep XML protocol found in the file system
  - $QCReport   : DTIPrep text QCReport found in the file system
  - $XMLReport  : DTIPrep XML QCReport found in the file system
  - $QCed\_minc  : QCed MINC file created after conversion of
                   QCed NRRD file
  - $QCed2\_minc : optional, secondary QCed MINC file created after
                   conversion of secondary QCed DTIPrep NRRD file
  - returns undef if one of the file listed above is missing (except
     for QCed2\_minc which is optional)

### checkPostprocessFiles($dti\_file, $DTIrefs, $mri\_files)

Function that checks if all postprocessing files (from DTIPrep or
mincdiffusion) are present in the file system.

INPUTS:
  - $dti\_file : raw DTI dataset that is used as a key in $DTIrefs hash
  - $DTIrefs  : hash containing all output paths and tool information
  - $mri\_files: list of processed outputs to register or that
                 have been registered

RETURNS:
  - $RGB\_minc       : RGB map
  - $FA\_minc        : FA map
  - $MD\_minc        : MD map
  - $baseline\_minc  : baseline (or frame-0) map
  - $brain\_mask\_minc: brain mask produced by mincdiffusion tools (not
                       available if DTIPrep was run to obtain the
                       post-processing outputs)
  - will return undef if one of the file listed above is missing

### getFileID($file, $src\_name)

Fetches the source FileID from the database based on the src\_name file
identified by getFileName.

INPUTS:
  - $file    : output filename
  - $src\_name: source filename (file that has been used to obtain the output
                file $file)

RETURNS: source File ID (file ID of the source file that has been used to
          obtain $file)

### getToolName($file)

Fetches tool information stored either in the MINC file's header or in the
QCReport.

INPUT: MINC or QC report to look for tool information

RETURNS:
  - $src\_pipeline: name of the pipeline used to obtain $file (DTIPrepPipeline)
  - $src\_tool    : name and version of the tool used to obtain $file
                    (DTIPrep\_v1.1.6, mincdiffusion\_v...)

### getPipelineDate($file, $data\_dir, $QCReport)

Fetches the date at which the DTIPrep pipeline was run either in the processed
MINC file's header or in the QCReport.

INPUTS:
  - MINC or QC report to look for tool information
  - data\_dir from the `Config` table
  - QC report created when `$file` was created

RETURNS: date at which the pipeline has been run to obtain `$file`

### insertReports($minc, $registeredXMLFile, $registeredQCReportFile)

Inserts the path to DTIPrep's QC text, XML reports and XML protocol in the
MINC file's header.

INPUTS:
  - $minc                  : MINC file for which the header should be modified
  - $registeredXMLfile     : path to the registered DTIPrep's XML report
  - $registeredQCReportFile: path to the registered DTIPrep's QC text report

RETURNS:
 - $Txtreport\_insert: 1 if on text report path insertion success,
                       undef otherwise
 - $XMLreport\_insert: 1 if on  xml report path insertion success,
                       undef otherwise

### insertPipelineSummary($minc, $data\_dir, $XMLReport, $scanType)

Inserts in the MINC header a summary of DTIPrep reports. This summary consists
of the directions rejected due to slice wise correlation, the directions
rejected due to interlace correlation, and the directions rejected due to
gradient wise correlation.

INPUTS:
  - $minc     : MINC file in which the summary will be inserted
  - $data\_dir : `data_dir` from the `Config` table
  - $XMLReport: DTIPrep's XML QC report from which the summary will be extracted

RETURNS: 1 on success, undef on failure

### registerFile($file, $src\_fileID, $src\_pipeline, $src\_tool, ...)

Registers file into the database via register\_processed\_data.pl with all
options.

INPUTS:
  - $file           : file to be registered in the database
  - $src\_fileID     : source file's FileID
  - $src\_pipeline   : pipeline used to obtain the file
                       (DTIPrepPipeline)
  - $src\_tool       : name and version of the tool
                       (DTIPrep or mincdiffusion)
  - $pipelineDate   : file's creation date (= pipeline date)
  - $coordinateSpace: file's coordinate space (= native, T1 ...)
  - $scanType       : file's scan type (= DTIPrepReg, DTIPrepDTIFA,
                       DTIPrepDTIMD, DTIPrepDTIColorFA...)
  - $outputType     : file's output type (.xml, .txt, .mnc...)
  - $inputs         : input files that were used to create the file to
                       be registered (intermediary files)

RETURNS: registered file

### fetchRegisteredFile($src\_fileID, $src\_pipeline, $pipelineDate, ...)

Fetches the registered file from the database to link it to the MINC files.

INPUTS:
 - $src\_fileID     : FileID of the source native file
 - $src\_pipeline   : pipeline name used to register the processed file
 - $pipelineDate   : pipeline data used to register the processed file
 - $coordinateSpace: processed file's coordinate space
 - $scanType       : scan type used to register the processed file
 - $outputType     : output type used to register the processed file

RETURNS: path to the registered processed file

### register\_DTIPrep\_files($minc, $nrrd, $raw\_file, $data\_dir, ...)

Registers DTIPrep NRRD and MINC files. The MINC file will have a link to the
registered NRRD file (`&register_minc` function will modify the MINC header to
include this information) in addition to the links toward QC reports and
protocol.

INPUTS:
  - $minc                   : MINC file to be registered
  - $nrrd                   : NRRD file to be registered
  - $raw\_file               : raw DWI file used to create the MINC file to
                               register
  - $data\_dir               : `data_dir` from the `Config` table
  - $inputs                 : input files that were used to create the file to
                               be registered (intermediary files)
  - $registeredXMLProtocolID: registered XML protocol file
  - $pipelineName           : name of the pipeline that created the file to be
                               registered (DTIPrepPipeline)
  - $DTIPrepVersion         : DTIPrep's version
  - $registeredXMLReportFile: registered XML report file
  - $registeredQCReport     : registered QC text file
  - $scanType               : scan type to use to label/register the MINC file

RETURNS: registered MINC files or undef on insertion's failure

### register\_nrrd($nrrd, $raw\_file, $data\_dir, $QCReport, $inputs, ...)

Sets parameters needed to register the NRRD file produced by DTIPrep
and calls registerFile to register the NRRD file via
`register_processed_data.pl`.

INPUTS:
  - $nrrd        : NRRD file to be registered
  - $raw\_file    : native DWI file used to obtain the DTIPrep outputs
  - $data\_dir    : data\_dir from the config table
                    (a.k.a. /data/project/data)
  - $QCReport    : DTIPrep QCreport
  - $inputs      : input files used to process data through DTIPrep
  - $pipelineName: pipeline name used to process DTIs
                    (DTIPrepPipeline)
  - $toolName    : DTIPrep name & version used to process the DWI file
  - $scanType    : NRRD file's scan type

RETURNS: registered NRRD file or undef on insertion's failure

### register\_Preproc($mri\_files, $dti\_file, $data\_dir, ...)

Gathers all DTIPrep preprocessed files to be registered in the database
and calls `&register_DTIPrep_files` on all of them. Will register first the
NRRD file and then the MINC file for each scan type.

INPUTS:
  - $mri\_files   : hash containing all DTI output information
  - $dti\_file    : native DWI file (that will be used as a key
                    for $mri\_files)
  - $data\_dir    : data\_dir defined in the config file
  - $pipelineName: pipeline name (DTIPrepPipeline)
  - $toolName    : tool's name and version
  - $process\_step: processing step ('Preproc' or 'Postproc')
  - $proc\_file   : processed file key ('QCed', 'QCed2'...)

RETURNS: path to the MINC file that was registered

### register\_images($mri\_files, $raw\_file, $data\_dir, $pipelineName, ...)

Function to register processed images in the database depending on the tool
used to obtain them. Will call `&register_DTIPrep_files` if files to be
registered are obtained via DTIPrep or `&register_minc` if files to be
registered are obtained using mincdiffusion tools.

INPUTS:
  - $mri\_files   : hash with information about the files to be registered
  - $raw\_file    : source raw image
  - $data\_dir    : data directory from the Config table
  - $pipelineName: name of the pipeline used (a.k.a DTIPrep)
  - $toolName    : tool's version and name
  - $process\_step: processing step (preprocessing, post-processing)

RETURNS:
  - @registered        : list of registered files
  - @failed\_to\_register: list of files that failed to be registered
                          in the DB

### getInputList($mri\_files, $data\_dir, $process\_step, $proc\_file)

Function that will return in a string the list of inputs used to process the
data separated by ';'.

INPUTS:
  - $mri\_files   : list of processed outputs to register or that
                    have been registered
  - $data\_dir    : data directory from the Config table
  - $process\_step: processing step used for the processed output
                    to determine inputs
  - $proc\_file   : processing file to determine inputs used

RETURNS: string with each inputs used separated by ';'

### fetchRegisteredMD5($md5sum)

Will check if md5sum has already been registered into the database.

INPUT: md5sum of the file

RETURNS:
  - $registeredFile    : registered FileID matching md5sum
  - $registeredScanType: scan type of the registered FileID matching md5sum

# TO DO

Nothing planned (or things that are left to do)

# BUGS

None reported (or list of bugs)

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

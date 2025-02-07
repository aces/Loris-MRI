# 2.0 - Install

## 2.1 Dependencies and installation

Dependencies and installation information are documented on the LORIS-MRI
  [README.md](../README.md) file.


## <a name="configuration"></a> 2.2 Configuration

Following a successful install, some configurations and customizations are 
needed and outlined in the next three sub-sections.

### 2.2.1 Database

The following tables in the database need to be configured properly for the 
insertion pipeline to successfully insert scans.

1. **`psc`** table

The `MRI_alias` field must be populated for each site that is scanning 
candidates or phantoms.

2. **`Visit_Windows`** table

To populate with visit labels, you can manually insert study-specific information:


      INSERT INTO Visit_Windows (Visit_label,  WindowMinDays, WindowMaxDays, OptimumMinDays, OptimumMaxDays, WindowMidpointDays) VALUES ('V1', '0', '100', '40', '60', '50');

If age is not a critical factor in study visit scheduling, define `Min` value as 
`0`, and `Max` value as `2147483647` (maximum `int`).


Alternatively, LORIS provides a PHP script called `populate_visit_windows.php` 
in its `tools/` directory that can be used.


4. **`mri_scan_type`**, **`mri_protocol`** and **`mri_protocol_checks`** tables

> - `mri_scan_type`: this table is a lookup table that stores the name of
the acquisition (*e.g.* t1, t2, flair...). Do not include commas, hyphens,
spaces or periods in your `mri_scan_type.Scan_type` column values. The ID
present in this table will be used in the `mri_protocol` and
`mri_protocol_checks` tables described below. The ID is also used in the
`bids_mri_scan_type_rel` table that will be described in 5.


> - `mri_protocol`: this table is used to identify incoming scans based
on their series description **OR** scan parameter values (TE, TR,
slice thickness, etc). By default, this table is populated with entries for t1,
t2, fMRI and DTI, and the columns defining expected scan parameters
(*e.g.* `TE_min`, `TE_max`) are defined very broadly.

> - `mri_protocol_checks`: this table allows further checking on the acquisition
once the scan type has been identified in order to flag certain scans based on
additional parameters found in the header. For example, let's say a scan has been
identified with the `mri_protocol` table to be a `t1`. Additional headers could
be checked in order to flag with a caveat or exclude the scan based on the value
of that header.

**Behaviour of the `*Min` and `*Max` columns of the `mri_protocol` and
`mri_protocol_checks` tables:**

> - if for a given parameter (*e.g.* TR) a `*Min` **AND** a `*Max` value have
been specified, then it will check if the parameter of the scan falls into the
range \[Min-Max].

> - if for a given parameter, a `*Min` is provided but not a `*Max` then the
imaging pipeline will check if the parameter of the scan is higher than
the `*Min` value specified in the table.

> - if for a given parameter, a `*Max` is provided but not a `*Min` then the
imaging pipeline will check if the parameter of the scan is lower than
the `*Max` value specified in the table.

> - if for a given parameter, both `*Min` and `*Max` are set to `NULL`, then
there will be no constraint on that header.



5. `bids_mri_scan_type_rel` and other `bids*` tables

The following tables are used by pipelines generating BIDS files either directly from DICOM files 
(using dcm2niix as a converter) or from the MINC files already inserted into the database.

> - `bids_mri_scan_type_rel`: this table maps a given scan type with BIDS labelling convention
that should be used to determine the name of the NIfTI and JSON files. This table also links
to the `mri_scan_type`, `bids_category`, `bids_phase_encoding_direction`, `bids_scan_type`
and `bids_scan_type_subcategory` tables.

> - `bids_category`: defined BIDS category corresponding to the
modality folder where the NIfTI and JSON files will go (examples: `anat`, `func`, `fmap`, `dwi`...)

> - `bids_scan_type`: defines BIDS scan types to be used to label
the NIfTI and JSON files (examples: `T1w`, `T2w`, `bold`, `dwi`, `FLAIR`, `magnitude`, `phasediff`)

> - `bids_scan_type_subcategory`: stores the series of entities used to label acquisitions
(may refer to a custom study protocol) within the NIfTI and JSON file names 
(e.g. `acq-25direction`, `task-rest`, `dir-AP`, `dir-PA`, `acq-B0_dir-AP`). Refer to the
[BIDS specification](https://bids-specification.readthedocs.io/en/stable/) for details on how to
label acquisitions.

> - `bids_phase_encoding_direction`: stores different phase encoding directions
possible (`i`, `-i`, `j`, `-j`, `k`, `-k`). Used by the mnc2bids conversion script to back-populate
this information (since it cannot be read from the MINC files' header unfortunately).

> - `bids_export*` tables: stores paths to BIDS files generated from a MINC dataset
by the mnc2bids conversion script (`tools/minc_to_bids_converter.pl`)

**Important note**
Please refer to the [BIDS specification](https://bids-specification.readthedocs.io/en/stable/) to find out
how to properly fill in the BIDS tables above so that it is fully standard-compliant.

6. **`Config`** table

The `Config` table can also be accessed and customized from the LORIS front-end
via the `Configuration` module, accessible under the `Admin` menu. Here are the 
configuration settings that impact directly or indirectly the pipeline:

Under the `Study` section:
 * `ImagingUploader Auto Launch`: used by the Imaging Uploader to automatically launch the insertion scripts on the uploaded scan
 
Under the `Paths` section: 
 * `LORIS-MRI Code`: where the LORIS-MRI codebase is installed; typically `/opt/$PROJECT/bin/mri/`
 * `MRI Incoming Directory`: where the uploaded scans get stored; typically `/data/incoming/`
 * `Images`: where the images displayed in Imaging Browser are stored; typically `/data/$PROJECT/data/`
 
Under the `Imaging Modules` section: 
  * `Patient ID regex`: used by the DICOM Archive module to show/hide the PatientID info
  * `Patient name regex`: used by the DICOM Archive module to show/hide the Patient Name info
  * `Lego phantom regex`: used by the DICOM Archive module to show/hide the Patient Name info for phantoms
  * `Living phantom regex`: used by the DICOM Archive module to show/hide the Patient Name info for phantoms
  * `Imaging Browser Tabulated Scan Types`: used by Imaging Browser's main page which lists the different imaging sessions across candidates. This setting will determine which modalities will have their QC status displayed in that listing page
     
Under the `Imaging Pipeline` section: 
 * `LORIS-MRI Data Directory`: directory where imaging data is stored;
    typically `/data/$PROJECT/data/`
 * `Study Name`: prefix to be used in all filenames inserted into the `files`
    table and visible in the front-end via the Imaging Browser module
 * `User to notify when executing the pipeline`: user email address to be used when
    notification is to be sent by the pipeline
 * `Full path to get_dicom_info.pl script`: typically `/opt/$PROJECT/bin/mri/dicom-arhive/get_dicom_info.pl`
 * `Horizontal pictures creation`: specifies whether or not argument -horizontal
    should be used by mincpik when generating pictures to be displayed in Imaging Browser
 * `NIfTI file creation`: used to enable or disable automated NIfTI file creation
 * `DICOM converter tool to use (dcm2mnc or dcm2niix)`: allows the user to specify the binary
    file to be used when converting DICOM files to MINC or NIfTI files. The default setting is to 
    use the binary provided by the MINC tools, namely `dcm2mnc` for studies wishing to generate MINC
    files. For studies that want BIDS dataset generated out of the DICOM files, then specify `dcm2niix`
 * `Path to Tarchives`: directory where the original DICOMs are archived;
    typically `/data/$PROJECT/data/tarchive/`
 * `Patient identifiers and center name lookup variable`: DICOM header that
    contains the LORIS candidate identifiers; typically `PatientName`
 * `Enable candidate creation`: enable or disable candidate creation into LORIS
    when running the insertion pipeline
 * `Enable visit creation`: enable or disable visit creation into LORIS
    when running the insertion pipeline
 * `Default project`: Default cohort used when Enable visit creation is set to true. This value is used when
   the following rules fails:
      - the $subjectID{'ProjectID'} is undef in the profileTemplate (prod) file;
      - the ProjectID from the session table, if the PSCID and visit labels exist;
      - the ProjectID from the candidate table, if the PSCID exists.
 * `Default cohort`: Default cohort used when Enable visit creation is set to true. This value is used when
   the following rules fails:
      - the $subjectID{'CohortID'} is undef in the profileTemplate (prod) file;
      - the CohortID from the session table, if the PSCID and visit labels exist;
      - the default_cohort DB config value.
 * `Default visit label for BIDS dataset`: the visit directory in BIDS
    structure is optional in the case of only one visit for the whole dataset. In
    this case, we need to specify to LORIS what would be the default visit label
    the project wants to use to store the electrophysiology datasets (*e.g.* V01).
 * `Project batch management used`: enable or disable batch management
 * `Number of volumes in native DTI acquisitions`: used by the DTIPrep pipeline
 * `Scan type of native T1 acquisition`: name as specified in the `mri_scan_type`
    table. Used by the DTIPrep pipeline
 * `Max number of DTI rejected directions for passing QC`: maximum number of
    directions that can be removed from a DTI scan to pass QC. Used by the DTIPrep pipeline
 * `NIAK Path`: Path to NIAK if MINC diffusion is to be run. Used by the DTIPrep pipeline
 * `Secondary QCed dataset`: path where a secondary QC'ed dataset is to be stored. Used by the DTIPrep pipeline
 * `Series description to exclude from imaging insertion`: series descriptions to be 
    excluded from the steps of the pipeline that start at, and follow the DICOM to 
    MINC conversion. Note that the series description entered in that field needs to
    be an exact match of what is present in the DICOM series description field.
 * `ComputeDeepQC`: enable or disable the automated computation of image quality
    control. Feature to be integrated in the code base in a **future** release.
 * `Name of the Perl MRI config file`: name of the perl-based MRI config file to use when running
    the Perl insertion scripts; typically `prod`; used when Auto launch is turned on.
 * `Name of the environment file`: name of the MRI environment file to source before
    running the insertion scripts; typically `environment`; used when Auto-launch
    is turned on for the pipeline.
 * `Modalities on which SNR should be calculated`: list of modalities/scan types on 
    which to compute SNR; typically all 3D images
 * `Scan type to use as a reference for defacing (typically T1W image)`: scan type
    name of the modality to use as a reference for defacing
 * `Modalities on which to run the defacing pipeline`: list of modalities/scan types
    on which the defacing algorithm should be run; typically any scan showing the 
    face of the candidate
 * `Name of the Python MRI config file`: name of the python-based MRI config file to use
    when running the Python insertion scripts (typically `database_config.py`)
    
Under the `MINC to BIDS Converter Tool Options` section: 
 * `BIDS Dataset Authors`: list of authors who should be included in the 
dataset_description.json BIDS file (generated by this script)
 * `BIDS Dataset Acknowledgments`: string with acknowledgment information to be used
when generating the dataset_description.json BIDS file
 * `BIDS Dataset README`: content of the BIDS README file to be generated by
`minc_to_bids_converter.pl`
 * `BIDS Validation options to ignore`: series of numbers referring to validation error checks
to be ignored when running the BIDS Validator on the generated BIDS dataset

### 2.2.2 LORIS

1. **Imaging Uploader**


Projects can upload scans and launch the pipeline in a variety of options 
detailed in the [PipelineLaunchOptions](05-PipelineLaunchOptions.md) section. 
Irrespective of the project's choice as to whether the imaging scan is to be 
uploaded through the Imaging Uploader GUI or not, pipeline insertion progress 
can be consulted through a live 'Log Viewer' panel.
Some settings need to be configured properly (`php.ini` variables, 
`MRI-Upload Directory` and `ImagingUploader Auto Launch`), and are documented in 
the [LORIS repository: Imaging Uploader Specification](https://github.com/aces/Loris/blob/main/modules/imaging_uploader/README.md).


2. **DICOM Archive**

This LORIS module provides a front-end display with the details of the archived 
DICOM study from the database `tarchive_*` tables. The only setting that 
impacts the display of this module are the regex settings in the `Configuration` 
module under the section `Imaging Modules`. These settings determine whether the 
Patient Name/Patient ID header values are displayed in full, or show up as 
**INVALID-HIDDEN**.

More detailed specifications can be consulted in the 
[LORIS repository: DICOM Archive Specification](https://github.com/aces/Loris/blob/main/modules/dicom_archive/README.md).


3. **Imaging Browser**

The Imaging Browser module accesses the screenshot (PIC) images directly from 
the filesystem where they are stored. It also provides the option to download 
some files. Ensure that:
- `/data/$PROJECT` directory and subdirectories are readable and executable by
    the Apache linux user.
- the Configuration module (*Paths*) `Images` setting is set (typically: `/data/$PROJECT/data/`). 
    
More detailed specifications can be consulted in the 
[LORIS repository: Imaging Browser Specification](https://github.com/aces/Loris/blob/main/modules/imaging_browser/README.md).

4. **Brainbrowser**

Brainbrowser displays the MINC (or NIfTI) images within the browser. It accesses those 
images directly from the filesystem. Ensure that:
- `/data/$PROJECT` directory and subdirectories are readable and executable by
    the Apache linux user.
- the Configuration module (*Paths*) `Images` setting is `/data/$PROJECT/data/`.
- the `project/config.xml` file (in the main LORIS codebase) contains the
      proper MINC toolkit path in the `<MINCToolsPath>` tagset.
      
More detailed specifications can be consulted in the 
[LORIS repository: Brainbrowser Specification](https://github.com/aces/Loris/blob/main/modules/brainbrowser/README.md).


5. **MRI Violated Scans**

No configuration setting is needed for the MRI Violated Scans module to work. 
Data loaded in this module gets populated automatically by the insertion 
scripts. As such, scans whose parameters can't be matched against the 
`mri_protocol` table during the imaging insertion process, will be flagged as 
protocol violations and will not have their MINC/NIfTI volumes loaded in the 
Imaging Browser module. Violated scans can be viewed and the type of error 
(scan identification, protocol violation) can be reviewed from the front-end.

More detailed specifications can be consulted in the 
[LORIS repository: MRI Violated Scans Specification](https://github.com/aces/Loris/blob/main/modules/mri_violations/README.md).


6. **Electrophysiology Browser**

No configuration setting is needed for the Electrophysiology Browser module. 
Data loaded in this module get populated automatically by the BIDS insertion 
scripts (in the `python` directory). It accesses data stored in the 
`physiological_*` tables.


### 2.2.3 LORIS-MRI 

#### Filesystem

- `/data/*` and `/opt/*` subdirectories were created by the imaging install script. If not,
    it may be due to `root:root` ownership of the `/data/` mount or `/opt` directory on your
    system. Ensure these subdirectories are created manually, particularly:
    `/opt/$PROJECT/bin/mri/`, `/data/incoming/`, and those inside 
    `/data/$PROJECT/data/`, namely `assembly`, `assembly_bids`, `batch_output`, `bids_imports`, `logs`,
    `pic`, `tarchive`, and `trashbin`.


- `/data/$PROJECT/` and `/opt/$PROJECT/` directory and subdirectories must be readable and executable
    by the Apache linux user. It may also help to ensure the `/data/` and `/opt/` mount is
    executable. After any modifications, ensure you restart apache.
    
#### Customizable routines in the Perl config file (a.k.a. `prod` under `dicom-archive/.loris_mri`)

- `isFileToBeRegisteredGivenProtocol()`

    * By default, any scan will be inserted if it matches an `mri_protocol` 
    table entry.
    * To **whitelist/blacklist** specific scan types -- *e.g.* in the case of 
    protocol exclusion, case sensitivity or labelling variance -- modify the 
    subroutine, *e.g.*:

```perl
if($acquisitionProtocol eq 't1' or $acquisitionProtocol eq 't2' or $acquisitionProtocol eq 'dti' or $acquisitionProtocol eq 'bold' or $acquisitionProtocol =~ /fmri/) { return 1; }
```

- `getSubjectIDs()`

    Routine to parse candidate’s PSCID, CandID, Center (determined from the PSCID), and visit 
    label. 
    
- `get_DTI_CandID_Visit()`

    Used by the DTIPrep pipeline
    
- `determineHRRTprotocol()`

    Routine to determine the acquisition protocol to use to register an HRRT derived
    file.

#### Customizable routines in the Python config file (`database_config.py` under `dicom-archive/.loris_mri`)

- `get_subject_ids`

    Routine to parse candidate's PSCID, CandID, Center (determined from the PSCID), and visit label.

## <a name="post-installation-checks"> 2.3 Post-installation checks

#### 2.3.1 Make sure the environment file is writable by Apache

To help ensure Apache-writability, verify that your environment file contains
  the following line:

 ```bash
 umask 0002
 ```

#### 2.3.2 Set up MINC utilities for BrainBrowser visualization

To ensure that BrainBrowser can load MINC images, the MINC toolkit must be
  accessible to the main LORIS codebase. (If the LORIS-MRI codebase is
  installed on a separate machine, ensure the MINC toolkit is installed in both
  locations.)

Ensure the `project/config.xml` file (in the main LORIS codebase) contains the
  following tagset, specifying the MINC toolkit path local to the main LORIS
  codebase (`/opt/minc/` in this example):

```xml
<!-- MINC TOOLS PATH -->
<MINCToolsPath>/opt/minc/</MINCToolsPath>
```

#### 2.3.3. Verify filesystem permissions

Ensure that permissions on `/data/$PROJECT`, `/data/incoming`, `/opt/$PROJECT` and their
  subdirectories are set such that `lorisadmin` and the Apache linux user can
  read, write _and_ execute all contents.

The following must be recursively owned by the `lorisadmin` user and Apache group:

```bash
/data/$PROJECT/data/
/data/$PROJECT/bin/mri/
/data/incoming/
/opt/$PROJECT/
/opt/$PROJECT/bin/mri/dicom-archive/.loris_mri/prod
```

#### 2.3.4 Verify Configuration module settings for Imaging Pipeline

In the LORIS front-end, under the Admin menu, go to the `Config` module.  Verify/set 
the following config settings (examples are shown below for a project named `demo`):

Under the `Imaging Pipeline` section:
 * `LORIS-MRI Data Directory` (typically `/data/$PROJECT/data/`)
 * `Study Name` (`exampleStudy`; this name will be appended as a prefix to the filenames in LORIS' Imaging Browser)
 * `User to notify when executing the pipeline`
 * `Full path to get_dicom_info.pl script`(typically `/opt/$PROJECT/bin/mri/dicom-archive/get_dicom_info.pl`)
 * `Path to Tarchives` (typically `/data/$PROJECT/data/tarchive/`)
 * `Default visit label for BIDS dataset`: (`V01` or any visit label fitting)
 * `DICOM converter tool to use (dcm2mnc or dcm2niix)`: must be used to specify which tool the pipeline 
   should run -- `dcm2mnc` to produce MINC files, or `dcm2niix` to produce BIDS-compatible files

Under the `Path` section:
 * `LORIS-MRI Code`(typically `/opt/$PROJECT/bin/mri/`)
 * `Images` (typically `/data/$PROJECT/data/`)

Click `Submit` at the end of the Configuration page to save any changes.

#### 2.3.5 Troubleshooting guideline

For common errors and frequently asked questions, please refer to the [Appendix
  A](AppendixA-Troubleshooting_guideline.md).


## 2.4 Pipeline flow

### 2.4.1 DICOM insertion (MRI/PET)

The pipeline was initially designed for **raw DICOM MRI data**, collected by a
  longitudinally-organized multi-site study with a defined imaging acquisition
  protocol. With modifications and further customization, it can handle any
  modality of imaging data.

Typically, images insertion into LORIS is performed via the following steps:

1. Upload of a compressed set of the DICOM study via the **Imaging Uploader**
     module (or transfer the compressed DICOM studies directly on the server
     hosting LORIS).
2. DICOM insertion into the `tarchive` tables in order to be able to see the
     information stored in the DICOMs via the **DICOM Archive** module.
3. Conversion of the DICOMs into MINC files (via dcm2mnc) or BIDS NIfTI and JSON 
     files (via dcm2niix). Those converted files undergo protocol validation and
     insertion into the LORIS database. By default, NIfTI images will be generated
     from the MINC files and inserted into LORIS when generating MINC files (see the
     [Configuration](#2.2-configuration) section above if you want to disable
     this option). One of two possible actions will follow depending on the
     study-defined protocol:
     
    a. If a scan matches one of the protocol defined in the `mri_protocol`
         table and passes the optional additional file checks present in the 
         `mri_protocol_checks` table, then the image will be stored into 
         the `files` tables. This inserted image is then accessible via the 
         **Imaging Browser** module and can be displayed in 3D using 
         **BrainBrowser**.

    b. If a scan does not match any of the protocol defined in the
         `mri_protocol` table, then the image will be stored
         in the `mri_protocol_violated_scans` table. Additionally, scans that
         were excluded by the optional criteria defined in the
         `mri_protocol_checks` table will be logged into the
         `mri_violations_log` table. Both types of violated scans are
         then accessible via the **MRI Violated Scans** module and can be
         displayed in 3D using **BrainBrowser**.


The graph below shows the different modules mentioned above with the
  representation of the group of tables described in more details in the
  [Technical Infrastructure](03-TechnicalInfrastructure.md) section. In
  addition, the graph shows the name of the main script that is used to insert
  the images into the LORIS database. More details about those scripts can be
  found in the [Scripts](04-Scripts.md) section.

![pipeline_flow](images/overall_flow.png)


### 2.4.2 PET data from an HRRT scanner

The pipeline was initially designed for **raw HRRT PET datasets collected at 
the Brain Imaging Center of the Montreal Neurological Institute**. Since there is
no standard for HRRT datasets and only 7 scanners existing in the world, the
insertion pipeline of PET data from an HRRT scanner might need to be updated/modified
for other scanners and will be done when the need comes.

Image insertion of PET dataset from an HRRT scanner is very similar to the 
insertion described for DICOM datasets, to the exception that the HRRT archive
information are stored in the `hrrt_archive` tables instead of the `tarchive` tables.

Insertion into LORIS is performed via the following steps:

1. Upload of a compressed set of the HRRT PET study via the **Imaging Uploader**
     module (or transfer the compressed HRRT PET studies directly on the server
     hosting LORIS).
2. HRRT insertion into the `hrrt_archive` tables.
3. Conversion of the ECAT7 files into MINC files for protocol identification and
     insertion into the LORIS database. Note that the ECAT7 images will be linked
     to the inserted MINC files. 
     

### 2.4.3 BIDS insertion (Electrophysiology and Imaging)

The pipeline to insert BIDS datasets into LORIS currently support the 
following BIDS modalities/entities:
  - Electroencephalography ('eeg')
  - Magnetic Resonance Imaging ('anat', 'func', 'fmap', 'dwi') 
  - Intracranial electroencephalography ('ieeg')
      - **Note:** optional [electrical stimulation](https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/04-intracranial-electroencephalography.html#electrical-stimulation) files for ieeg modality are currently not supported in LORIS-MRI (or LORIS). 
      If a BIDS-IEEG directory includes these files, they will be ignored during the import process. 

With slight modifications and further customization, it could handle other 
types of electrophysiology or imaging modalities.

Typically, BIDS data insertion into LORIS is performed via the following steps:

1. Transfer the BIDS-format data to the LORIS server via commandline. Due to the 
large size of electrophysiological/BIDS data, a suitable browser-based uploader is 
not presently available.

2. Run the BIDS import script to import the data into the `physiological_*` tables 
for electrophysiology datasets and into the `file*` tables of LORIS. More details about this import script can 
be found in the [PipelineLaunchOptions](05-PipelineLaunchOptions.md) section.

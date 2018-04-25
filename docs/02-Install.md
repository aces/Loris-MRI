# 2.0 - Install

## 2.1 Dependencies and installation

Dependencies and installation information are documented on the LORIS-MRI
  [README.md](../README.md) file.


## 2.2 Configuration

Following a successful install, some configurations and customizations are 
needed and outlined in the next three sub-sections.

### 2.2.1 Database
The following tables in the database need to be configured properly for the 
insertion pipeline to successfully insert scans.

1. **`psc`** table

The `MRI_alias` field must be populated for each site that is scanning 
candidates or phantoms.

2. **`Visit_Windows`** table

To populate with visit labels, you can manually insert study-specific 
information:


      INSERT INTO Visit_Windows (Visit_label,  WindowMinDays, WindowMaxDays, OptimumMinDays, OptimumMaxDays, WindowMidpointDays) VALUES ('V1', '0', '100', '40', '60', '50');

If age is not a critical factor in study visit scheduling, define Min value as 
0, and Max value as 2147483647 (maximum `int`).


Alternatively, LORIS provides a PHP script in its `tools/` directory 
`populate_visit_windows.php` that can be used.


4. **`mri_scan_type`** and **`mri_protocol`** tables

Ensure your `mri_scan_type` and `mri_protocol` tables contains an entry for 
each type of scan in the study protocol.
The `mri_protocol` table is used to identify incoming scans based on their 
SeriesDescription **OR** scan parameter values (TE, TR, slice thickness, etc). 
By default, this table is populated with entries for t1, t2, fMRI and DTI, and 
the columns defining expected scan parameters (e.g. `TE_Range`) are defined very 
broadly.  
The `Scan_type` column values are defined in the `mri_scan_type` table 
(e.g. 44=t1); do not include hyphens, spaces or periods in your 
`mri_scan_type.Scan_type` column values.

5. **`Config`** table

The `Config` table can also be accessed and customized from the LORIS front-end
via the `Configuration` module, accessible under the Admin menu. Here are the 
configuration settings that impact directly or indirectly the pipeline:

Under the section `Study`:
 * `ImagingUploader Auto Launch`: Used by the Imaging Uploader to automatically launch the insertion scripts on the uploaded scan
 
Under the section `Paths`
 * `Imaging Data`: Where the imaging data is stored; typically `/data/$PROJECT/data/`
 * `LORIS-MRI Code`: Where the MRI code base is installed; typically `/data/$PROJECT/bin/mri/`
 * `MRI-Upload Directory`: Where the uploaded scans get stored; typically `/data/incoming/`
 * `MINC Files`: Where the MINC images are stored; typically `/data/$PROJECT/data/`
 * `Images`: Where the images displayed in Imaging Browser are stored; typically `/data/$PROJECT/data/`
 
 Under the section `Imaging Modules`
  * `Patient ID regex`: Used by the DICOM Archive module to show/hide the PatientID info
  * `Patient name regex`: Used by the DICOM Archive module to show/hide the Patient Name info
  * `Lego phantom regex`: Used by the DICOM Archive module to show/hide the Patient Name info for phantoms
  * `Living phantom regex`: Used by the DICOM Archive module to show/hide the Patient Name info for phantoms
  * `Imaging Browser Tabulated Scan Types`: Used by Imaging Browser main page which lists the different imaging sessions across candidates. This setting will determine which modalities will have their QC status displayed in that listing page
     
 Under the section `Imaging Pipeline`
 * `Loris-MRI Data Directory`: Directory where imaging data is stored; typically `/data/$PROJECT/data/`
 * `Study Name`: Prefix to be used in all filenames inserted into the `files` table and visible in the front-end via the Imaging Browser module
 * `User to notify when executing the pipeline`: User email address to be used when notification is to be sent by the pipeline
 * `Full path to get_dicom_info.pl script`: Typically `/data/$PROJECT/bin/mri/dicom-arhive/get_dicom_info.pl`
 * `Horizontal pictures creation`: Used to pass or not pass the argument `-horizontal` to `mincpik` when generating pictures to be displayed in Imaging Browser. 
 * `NIfTI file creation`: Used to enable or disable automated NIfTI file creation
 * `dcm2mnc binary to use when converting`: Allows the user to specify the binary file to be used when converting DICOM files to MINC. The default setting is to use the binary provided by the MINC tools, namely `dcm2mnc
 * `Path to Tarchives`: Directory where the original DICOMs are archived; typically `/data/$PROJECT/data/tarchive/`
 * `Upload creation of candidates`: Enable or disable candidate creation into LORIS when running the insertion pipeline
 * `Project batch management used`: Enable or disable batch management
 * `If site is used`: Obsolete **To be confirmed**. This option used to allow the scans' incoming and archival paths to be configured based on the scanning sites
 * `Number of volumes in native DTI acquisitions`: Used by the DTIPrep pipeline
 * `Scan type of native T1 acquisition`: Name as specified in the `mri_scan_type` table. Used by the DTIPrep pipeline
 * `Max number of DTI rejected directions for passing QC`: Number of directions that can be rejected and still pass QC. Used by the DTIPrep pipeline
 * `NIAK Path`: Path to NIAK if MINC diffusion is to be run. Used by the DTIPrep pipeline
 * `Secondary QCed dataset`: Path where a secondary QC'ed dataset is to be stored. Used by the DTIPrep pipeline


### 2.2.2 LORIS

1. **Imaging Uploader**


Projects can upload scans and launch the pipeline in a variety of options 
detailed in [PipelineOptions](05-PipelineOptions.md). 
Irrespective of the project's choice as to whether the imaging scan is to be 
uploaded through the Imaging Uploader GUI or not, pipeline insertion progress 
can be consulted through a live 'Log Viewer' panel.
Some settings need to be configured properly (`php.ini` variables, 
`MRI-Upload Directory` and `ImagingUploader Auto Launch`), and are documented in 
the [LORIS repository: Imaging Uploader Specification](https://github.com/aces/Loris/blob/master/modules/imaging_uploader/README.md).


2. **DICOM Archive**

This LORIS module provides a front-end display of the details of the archived 
DICOMs from the database `tarchive_*` tables. The only setting that impacts the 
display of this module are the regex settings in the `Configuration` module 
under the section `Imaging Modules`. These settings determine whether the 
Patient Name/Patient ID header values are displayed in full, or show up as 
**INVALID-HIDDEN**.

More detailed specifications can be consulted in the 
[LORIS repository: DICOM Archive Specification](https://github.com/aces/Loris/blob/master/modules/dicom_arhive/README.md).


3. **Imaging Browser**

Imaging Browser accesses the PIC images directly from the filesystem where they
are stored. It also provides the option to doownload some files.  Ensure that:
- `/data/$PROJ` directory and subdirectories are readable and executable by
    the Apache linux user.
- the Configuration module (*Paths*) `Imaging data`, `MINC files` and 
  `Images` settings are set (typically: `/data/$PROJECT/data/`). 
    
More detailed specifications can be consulted in the 
[LORIS repository: Imaging Browser Specification](https://github.com/aces/Loris/blob/master/modules/imaging_browser/README.md).

4. **Brainbrowser**

Brainbrowser displays the MINC images within the browser. It accesses those MINC 
images directly from the filesystem. Ensure that:
- `/data/$PROJ` directory and subdirectories are readable and executable by
    the Apache linux user.
- the Configuration module (*Paths*) `MINC files` setting is
    `/data/$PROJ/data/`.
- the _project/config.xml_ file (in the main LORIS codebase) contains the
      proper MINC toolkit path in the `<MINCToolsPath>` tagset.
      
More detailed specifications can be consulted in the 
[LORIS repository:Brainbrowser Specification](https://github.com/aces/Loris/blob/master/modules/brainbrowser/README.md).


5. **MRI Violated Scans**

No configuration setting is needed for the MRI Violated Scans module to work. 
Data loaded in this module gets populated automatically by the insertion 
scripts. As such, scans whose parameters can't be matched against the 
`mri_protocol` table during the imaging insertion process, will be flagged as 
protocol violations and will not have their MINC/NIfTI volumes loaded in the 
database. The type of error (scan identification, protocol violation) will be 
listed and can be reviewed from the front-end.

More detailed specifications can be consulted in the 
[LORIS repository:MRI Violated Scans Specification](https://github.com/aces/Loris/blob/master/modules/mri_violations/README.md).


### 2.2.3 LORIS-MRI 

#### Filesystem

- `/data/*` subdirectories were created by the imaging install script. If not,
    it may be due to `root:root` ownership of the `/data/` mount on your
    system. Ensure these subdirectories are created manually, particularly:
    `/data/$PROJ/data/*`, `/data/$PROJ/bin/mri/` and `/data/incoming/`

- `/data/$PROJ/` directory and subdirectories must be readable and executable
    by the Apache linux user. It may also help to ensure the `/data/` mount is
    executable. After any modifications, ensure you restart apache.
    
#### Customizable routines in the `prod` file

- `isFileToBeRegisteredGivenProtocol()`

    * By default, any scan will be inserted if it matches an _mri_protocol_ 
    table entry.
    * To **whitelist/blacklist** specific scan types -- e.g. in the case of 
    protocol exclusion, case sensitivity or labelling variance -- modify the 
    subroutine, e.g.:

```perl
if($acquisitionProtocol eq 't1' or $acquisitionProtocol eq 't2' or $acquisitionProtocol eq 'dti' or $acquisitionProtocol eq 'bold' or $acquisitionProtocol =~ /fmri/) { return 1; }
```

- `getSNRModalities()`
    
    Routine to instruct the pipeline which 3-D modalities to include when 
    computing the signal-to-noise-ratio (SNR) on MINC images.

- `getSubjectIDs()`

    Routine to parse candidate’s PSCID, CandID, Center (determined from the PSCID), and visit 
    label. 

- `filterParameters()`

    Routine that takes in a file as an object and removes all parameters of lenngth > 1000
    
- `get_DTI_Site_CandID_Visit()`

    Used for the DTIPrep pipeline


## 2.3 Post-installation checks

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

Ensure the _project/config.xml_ file (in the main LORIS codebase) contains the
  following tagset, specifying the MINC toolkit path local to the main LORIS
  codebase (/opt/minc/ in this example):

```xml
<!-- MINC TOOLS PATH -->
<MINCToolsPath>/opt/minc/</MINCToolsPath>
```

#### 2.3.3. Verify filesystem permissions

Ensure that permissions on /data/$projectname and /data/incoming and their
  subdirectories are set such that lorisadmin and the Apache linux user can
  read, write _and_ execute all contents.

The following must be recursively owned by the lorisadmin user and by Apache
  group:

```bash
/data/$projectname/data/
/data/$projectname/bin/mri/
/data/incoming/
/data/$projectname/bin/mri/dicom-archive/.loris_mri/prod
```

#### 2.3.4 Verify Configuration module settings for Imaging Pipeline

In the LORIS front-end, under the Admin menu, go to the `Config` module.  Verify/set the following config settings (examples below illustrated for a project named `demo`):

Under the section `Imaging Pipeline`:
 * `Loris-MRI Data Directory` (typically `/data/demo/data/`)
 * `Study Name` (`exampleStudy`; this name will be appended as a prefix to the filenames in LORIS' Imaging Browser)
 * `User to notify when executing the pipeline`
 * `Full path to get_dicom_info.pl script`(typically `/data/demo/bin/mri/dicom-archive/get_dicom_info.pl`)
 * `Path to Tarchives` (typically `/data/demo/data/tarchive/`)

Under the section `Path`:
 * `Imaging Data` (typically `/data/demo/data/`)
 * `LORIS-MRI Code`(typically `/data/demo/bin/mri/`)
 * `MINC files` (typically `/data/demo/data/`)
 * `Images` (typically `/data/demo/data/`)

Click 'Submit' at the end of the Configuration page to save any changes.

#### 2.3.5 Troubleshooting guideline

For common errors and frequently asked questions, please refer to the [Appendix
  A](AppendixA-Troubleshooting_guideline.md).


## 2.4 Pipeline flow

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
3. Conversion of the DICOMs into MINC files for protocol validation and
     insertion into the LORIS database. By default it will also create NIfTI
     images from the MINC files and insert them into LORIS (see the
     [Configuration](#2.2-configuration) section above if you want to disable
     this option). One of two possible actions will follow depending on the
     study-defined protocol:
     
    a. If a scan matches one of the protocol defined in the `mri_protocol`
         table and passes the optional additional file checks present in the 
         `mri_protocol_checks` table, then the MINC image will be stored into 
         the `files` tables. This inserted image is then accessible via the 
         **Imaging Browser** module and can be displayed in 3D using 
         **BrainBrowser**.

    b. If a scan does not match any of the protocol defined in the
         `mri_protocol` table, then the MINC image of this scan will be stored
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


# 2.0 - Install

## 2.1 Dependencies

- Perl
- MINC toolkit (step 3 of the [Setup](#2.2-setup) section below)
- DICOM toolkit (step 4 of the [Setup](#2.2-setup) section below)

On Ubuntu, DICOM toolkit will be installed by the imaging install script 
  (step 4 of [the Setup](#2.2-setup) section below). This script will 
  `apt-get install dcmtk`.
  
For CentOS: [an older transcripts](https://github.com/aces/Loris/wiki/CentOS-Imaging-installation-transcript) 
  is available for CentOS installation and includes notes on dependencies 
  including DICOM toolkit.

The following installation should be run by the `$lorisadmin` user. `sudo` 
  permission is required. See [aces/Loris](https://github.com/aces/Loris) 
  README.md for further information.


## 2.2 Installation

**1. Create directories and download LORIS-MRI code**

Replace in the lines below `$projectname` by your project's name.

```
sudo mkdir -p /data/$projectname/bin/mri
sudo chown -R lorisadmin:lorisadmin /data/$projectname
cd /data/$projectname/bin
git clone -b master https://github.com/aces/Loris-MRI.git mri
```
       
**2. Install MINC toolkit from
       [http://bic-mni.github.io/](http://bic-mni.github.io/)**
       
- Download the pre-compiled package for your operating system. 
- Install required dependencies such as `imagemagick`. 
- Then install your MINC toolkit package:

```
sudo dpkg -i minc-toolkit<version>.deb
```
- Finally, source the MINC toolkit environment by running:
  - for bash: `source /opt/minc/minc-toolkit-config.sh` 
  - for tcsh: `source /opt/minc/minc-toolkit-config.csh`

**3. Run installer to set up directories, configure environment, install Perl
 libraries and DICOM toolkit**

```
cd /data/$projectname/bin/mri/
bash ./imaging_install.sh
```

You will be asked for the following input:

- What is the database name? *$dbname*
- What is the database host? *$dbhost*
- What is the MySQL user? *$lorisuser* [Use the same MySQL user from the LORIS 
    installation, i.e. *lorisuser*]
- What is the MySQL password?
- What is the Linux user which the installation will be based on? *$lorisadmin*
- What is the project name? *$projectname*
- What is your email address?
- What prod file name would you like to use? default: prod [leave blank]
- Enter the list of Site names (space separated): *site1 site2*

If the imaging install script reports errors in creating directories (due to 
  `/data/ mount` permissions), review and manually execute `mkdir/chmod/chown`
  commands starting at [imaging_install.sh:L97](https://github.com/aces/Loris-MRI/blob/master/imaging_install.sh#L97)

Note: The installer will allow Apache to write to the `/data/` directories by 
  adding user *lorisadmin* to the Apache linux group. To ensure this change 
  takes effect, log out and log back into your terminal session before running 
  the imaging pipeline. The installer will also set Apache group ownership of
  certain `/data/` subdirectories.
 
**4. Configure paths and environment**

To help ensure Apache-writability:

- Verify that your environment file contains the following line:

```
umask 0002
```

- Ensure that /home/lorisadmin/.bashrc includes the statement:

```
source /data/$projectname/bin/mri/environment
```

- Then source the *.bashrc* file.

**5. Set up MINC utilities for BrainBrowser visualization**

To ensure that BrainBrowser can load MINC images, the MINC toolkit must be 
  accessible to the main LORIS codebase. (If the Loris-MRI codebase is 
  installed on a separate machine, ensure the MINC toolkit is installed in 
  both locations.)

Ensure the *project/config.xml* file (in the main LORIS codebase) contains the 
  following tagset, specifying the MINC toolkit path local to the main LORIS 
  codebase (`/opt/minc/` in this example):
```
<!-- MINC TOOLS PATH -->
<MINCToolsPath>/opt/minc/</MINCToolsPath>
```

**6. Verify filesystem permissions**

Ensure that permissions on `/data/$projectname` and `/data/incoming` and their 
  subdirectories are set such that *lorisadmin* and the Apache linux user can 
  read, write *and* execute all contents.

The following must be recursively owned by the lorisadmin user and by Apache 
  group:
```
/data/$projectname/data/ 
/data/$projectname/bin/mri/
/data/incoming/
/data/$projectname/bin/mri/dicom-archive/.loris_mri/prod
```  

**7. Verify Configuration module settings for Imaging Pipeline**

In the LORIS front-end, under the Admin menu, go to the Config module. Under 
the section `Imaging Pipeline`, verify/set the following config settings:

- `Loris-MRI Data Directory`
- `Study Name`
- `User to notify when executing the pipeline`
- `Full path to get_dicom_info.pl script`
- `Path to Tarchives`

Click 'Submit' at the end of the Configuration page to save any changes.


Installation complete.
For customizations and protocol configurations, see LORIS Imaging 
  [Setup](#2.3-setup) Guide below.


## 2.3 Setup

### 2.3.1 Set up imaging insertion scripts 

Populating a few database tables and configuration settings will tell the 
  imaging insertion scripts how and where to load scans:
  
**1. Configuration module**

Within the following sections:

- *Imaging Pipeline*: Verify all paths
- *WWW*: Verify Host and URL
- *Paths*: Verify `LORIS-MRI code`, `MRI-Upload Directory`, `Images` settings
- *Study*: Set `ImagingUploader Auto-Launch` to `Yes` only if files should be 
    automatically inserted after they are uploaded to the server. For initial
    upload troubleshooting, it is recommended to leave the default `No`.
- *DICOM Archive section*: Enter regex pattern to detect and mask identifying 
    information in `PatientID` or `PatientHeader` values, for display in the 
    DICOM Archive module. Populate the Living and Lego Phantom regex fields to 
    identify these special scans.
    
**2. `psc` table**

The `MRI_alias` field must be populated for each site that is scanning 
  candidates or phantoms.
  
**3. `Visit_Windows` table**

Ensure the [Visit Windows](https://github.com/aces/Loris/wiki/Project-Customization#iv-visit-windows) 
  table is fully populated with all valid Visit Labels. Scans will be identified
  and loaded based on these entries.

**4. `mri_protocol` table**

Ensure your `mri_protocol` table contains an entry for each type of scan in the 
  study protocol. The `mri_protocol` table is used to identify incoming scans 
  based on their SeriesDescription and scan parameter values (TE, TR, slice 
  thickness, etc). By default, this table is populated with entries for t1, t2, 
  fMRI and DTI, and the columns defining expected scan parameters (e.g. 
  `TE_Range`) are defined very broadly.

Note: `Scan_type` column values are defined in the `mri_scan_type` table 
  (e.g. 44=t1); do not include hyphens, spaces or periods in your 
  `mri_scan_type.Scan_type` column values.

**Notes on Scan type identification**

- By default, any scan will be inserted if it matches an `mri_protocol` table 
    entry.
- To **force-load** a specific MRI acquisition go to 
    [bypassing protocol violation checks](#bypassing-protocol-violation-checks)
- To **whitelist/blacklist** specific scan types -- e.g. in case of protocol 
    exclusion, case sensitivity or labelling variance -- modify the subroutine 
    `isFileToBeRegisteredGivenProtocol()` in your prod file 
    (`/data/$PROJ/bin/mri/dicom-archive/.loris_mri/prod`) e.g.:
```
if($acquisitionProtocol eq 't1' or $acquisitionProtocol eq 't2' or $acquisitionProtocol eq 'dti' or $acquisitionProtocol eq 'bold' or $acquisitionProtocol =~ /fmri/) { return 1; }
```

### 2.3.2 Set up the Imaging Uploader module

The Imaging Uploader module provides a user-friendly interface for transferring 
  an imaging dataset to the Loris server, before it is handled by the imaging 
  pre-processing and insertion pipeline scripts.
  
To configure the Imaging Uploader module for upload and insertion of scans via 
  a browser, see the [Imaging Uploader Readme](https://github.com/aces/Loris/blob/master/modules/imaging_uploader/README.md) 
  (within modules/imaging_uploader folder).
  
> **Missing visit label options?** The Imaging Uploader's Visit label options 
    are drawn from the list of all timepoints registered in the database *where 
    CenterID != 1* (this CenterID is reserved for 
    [DCC candidates](https://github.com/aces/Loris/wiki/Project-Customization#4-define-study-sites)
    ). If you do not see a particular visit label option in the Uploader's  
    dropdown select, simply create a new timepoint for any (non-DCC) 
    candidate with that visit label (via Candidate menu, Access Profiles). 
    The visit label should then automatically appear in the Uploader's 
    dropdown options.

#### Post-Upload: Pre-processing and Insertion into Loris

After an imaging dataset is uploaded to the Loris server, run the script 
  `imaging_upload_file.pl` to run the pre-processing and insertion pipeline 
  scripts that load the imaging data into the Loris database tables. Provide 
  the upload_id value and uploaded dataset name (e.g. 608, 
  AAA0001_513067_V01.zip):
```
cd /data/$PROJ/bin/mri
uploadNeuroDB/imaging_upload_file.pl -profile prod -verbose -upload_id 608 /data/incoming/AAA0001_513067_V01.zip 
```

See also: [Logs](#logs) and 
  [Troubleshooting Insertion of Uploaded Datasets](#troubleshooting-insertion-of-uploaded-datasets)

For more details on the different possibilities available to run the insertion 
  pipeline, please refer to [05-PipelineOptions](05-PipelineOptions.md).

#### Setting up Imaging AutoLaunch

- To automatically preprocess, validate and insert all uploaded scans into the
    database, set *ImagingUploader Auto-Launch* to "Yes" in the `Config` module, 
    "Study" section.
- For initial setup and configuration, it is recommended to 
    [manually run the imaging pipeline scripts](#post-upload:-pre-processing-and-insertion-into-loris) 
    for each uploaded dataset.
- Note that your *lorisadmin* user must also be part of the apache group (e.g. 
    www-data).

##### Server Processes Manager

The Server Processes Manager module (Admin menu) shows all server jobs launched 
  by Imaging Uploader. The exact Output and Error file names for each 
  upload/insertion are easily found in this module. The Exit Code file 
  describes the exit status of the job.

Caveat: By default these log files are output to `/tmp/` and deleted. To avoid 
  deletion, edit [deleteProcessFiles()](https://github.com/aces/Loris/blob/master/modules/server_processes_manager/php/AbstractServerProcess.class.inc#L521)
  to return false. (See also: [Logs](#logs)).
  
### 2.3.3 Queue Manager (optional/recommended)

Installing Sun GridEngine (SGE) is useful for managing the server processing 
  load for all scripts. Use the `Configuration` module setting `isqsub` to tell 
  the pipeline whether a queue manager is installed.

### 2.3.4 Email Notifications

Installing a mail server is recommended, as the LORIS Imaging pipeline by 
  default attempts to send notifications about completed or failed uploads.

### 2.3.5 Visualization: [BrainBrowser](https://brainbrowser.cbrain.mcgill.ca/)

[BrainBrowser](https://brainbrowser.cbrain.mcgill.ca/), a web-enabled viewer for
   real-time exploration of 3D images, comes embedded within LORIS, including 
   a 2D Volume viewer that can overlay 2 acquisitions. A 3D surface viewer 
   can be used for processed surface datasets.
   
See also: [BrainBrowser Troubleshooting](#2.5.3-brainbrowser-troubleshooting)

### 2.3.6 Quality Control within the Imaging Browser

The Imaging Browser module enables web-based Quality Control (QC) of 
  acquisitions.

MRI scans can be viewed in 3D space using the embedded BrainBrowser 
  visualization tool.

QC flags, comments and statistics are fully integrated and can be enabled by:

- Grant QC permissions in User Accounts (or add `mri_feedback` permission via 
    `user_perm_rel` table).
- Scan types will be populated automatically once images are inserted in the 
    database. Use the "Selected" dropdown to identify the single best 
    acquisition for a given type (e.g. t1) for the scan session.
- QC comments should already be enabled via the `feedback_mri_comment_types` 
    table.

## 2.4 Configuration

## 2.5 Pipeline flow

By default the pipeline is designed for **raw DICOM MRI data**, collected by a
  longitudinally-organized multisite study with a defined data acquisition
  protocol. With modifications and further customization, it can handle any
  modality of imaging data.

Default images insertion into LORIS follows the following steps:

1. Upload of a zip of the DICOM study via the **Imaging Uploader** module (or
     DICOM study transfer directly on the server hosting LORIS).
2. DICOM insertion into the `tarchive` tables in order to be able to see the
     information stored in the DICOMs via the **DICOM Archive** module.
3. Conversion of the DICOMs into MINC files for protocol validation and
     insertion into the LORIS database. By default it will also create NIfTI
     images from the MINC files and insert them into LORIS. See the
     [Configuration](#2.3-configuration) section above if you want to disable
     this option.
     
    a. If a scan matches one of the protocol defined in the `mri_protocol`
         table, then the MINC image will be stored into the `files` tables and
         can be visualized in the **Imaging Browser** module and
         **BrainBrowser**.

    b. If a scan does not match any of the protocol defined in the
         `mri_protocol` table, then the MINC image of this scan will be stored
         into the `mri_protocol_violated_scans` table and can be seen via the
         **MRI Violated Scans** module.


The graph below shows the different modules mentioned above with the
  representation of the group of tables described in more details in the
  [Technical Infrastructure](03-TechnicalInfrastructure.md) section. In
  addition, the graph shows the name of the main script that is used to insert
  the images into the LORIS database.

![pipeline_flow](images/overall_flow.png)


## 2.5 Common errors

### 2.5.1 Installation trouble shooting notes

Key configuration points to verify:

- `/data/*` subdirectories were created by the imaging install script. If not,
    it may be due to `root:root` ownership of the `/data/` mount on your 
    system. Ensure these subdirectories are created manually, particularly: 
    `/data/$PROJ/data/*`, `/data/$PROJ/bin/mri/` and `/data/incoming/`
    
- `/data/$PROJ/` directory and subdirectories must be readable and executable 
    by the Apache linux user. It may also help to ensure the `/data/` mount is 
    executable. After any modifications, ensure you restart apache.

- Depending on your operating system, some dependencies might be missing. 
    During initial troubleshooting of the imaging pipeline, note any related 
    error messages (e.g. `install_driver(mysql) failed: Can't locate DBD/mysql
   .pm`) and install missing packages as needed (e.g. 
   `sudo apt-get install libdbi-perl`, `sudo apt-get install libdbd-mysql-perl`,
    `sudo apt-get install libarchive-zip-perl`).

- If your MINC toolkit is older than 1.9.14 and your scans have no Date of Birth
   value, you may see an age unit error during DICOM to MINC conversion. 
   Instructions for compiling a more recent version available on 
   [MNI-BIC GitHub](https://github.com/BIC-MNI/minc-toolkit-v2).

### 2.5.2 Verify loaded images and Troubleshooting

Once an MRI scan session has been successfully inserted, it will be listed in 
  the Imaging Browser main data table (also linked from the Dicom Archive 
  subpage: "View Images").

Verify in the Imaging Browser's View Session page that a jpg showing 3 slice 
  orientations displays properly; if not, verify your permissions and restart 
  apache:
```
sudo chmod o+r /data/$PROJ/bin
sudo chmod o+r /data/$PROJ/data 
sudo service apache2 restart
```

If download links do not work, ensure that the `/data/$PROJ/data/assembly` 
  directory and subdirectories are executable.

#### Logs

Error and output messages from the imaging insertion scripts are logged in files
  created under the `/data/$PROJ/data/logs/` directory. To view messages from 
  the last script run, consult the most recent log file modified in this 
  directory. These log files reference an *uploadID* used to identify each 
  imaging dataset -- consult the `mri_upload` database table to look up which 
  uploadID has been assigned to your scans.

***Caveat:*** When the imaging insertion pipeline is auto-launched by the 
  Imaging Uploader module, the pipeline scripts' log files are output to 
  `/tmp/` and deleted. To avoid deletion, edit the Server Processes Manager 
  function [deleteProcessFiles()](https://github.com/aces/Loris/blob/master/modules/server_processes_manager/php/AbstractServerProcess.class.inc#L521) 
  to return false instead of true.

#### Troubleshooting Insertion of uploaded datasets

If upload was successful but issues were encountered with the imaging insertion 
  pipeline scripts:

- CentOS: check for additional dependencies/configurations (e.g. Dicom 
    Dictionary path) in the detailed 
    [CentOS Imaging Installation transcript](https://github.com/aces/Loris/wiki/CentOS-Imaging-installation-transcript)
- Manually re-run the entire pipeline sequence: 
    [imaging_upload_file.pl](#post-upload:-pre-processing-and-insertion-into-loris)
- If one of the final steps such as the MINC conversion is failing, you may 
    wish to just re-run the tarchiveLoader script.
- See also [re-running the Imaging pipeline](#rerunning-the-imaging-pipeline) 
    section for troubleshooting information.

#### Protocol violations

Scans whose parameters can't be matched against the `mri_protocol` table during 
  the imaging insertion process, will be flagged as protocol violations and 
  will not have their minc/nifti volumes loaded in the database. Review these
  in the front-end *Mri Violations* module (Imaging menu). The type of error 
  (scan identification, protocol violation) will be listed.

> see also notes on on protocol checks and flagging of protocol violations in 
[LORIS MRI Pipeline Flowchart](https://drive.google.com/file/d/0B3CILaw6mATHU0huc192R2I4MXM/view)

##### Bypassing protocol violation checks

For cases when a scan has triggered a protocol violation, the minc volume can be
  **force-loaded** into LORIS by running:
```
uploadNeuroDB/minc_insertion.pl -acquisition_protocol t2w -bypass_extra_file_checks -create_minc_pics -profile prod -globLocation -force  -tarchivePath _/data/project/dataTransfer/library/2009/DCM_2009-09-25_project_20110214_185904581.tar_ -mincPath _/data/project/data/trashbin/TarLoad-3-34-pVzGC5/xxx0067_703739_v12_20090925_222403_18e1_mri.mnc_
```

Note carefully the following arguments:

- *acquisition_protocol*: must be a known scan type according to the 
    `mri_scan_type` table
- *tarchive_Path*: the DICOM tarball
- *mincPath*: note this file may haven placed in the `trashbin` directory

See also: [MRI-PR#141](https://github.com/aces/Loris-MRI/pull/141) for more 
  examples.

#### Rerunning the Imaging pipeline

> When the need arises to re-load imaging data in LORIS, it is generally not 
   sufficient to just re-run the minc/nifti loading step (`tarchiveLoader` or
    `batch_uploads_tarchive`). The pipeline steps must be re-run starting 
    with dicomTar.pl (see section 5.4 of 
   [Pipeline triggering options](05-PipelineOptions.md)).
   
In general, to re-load an imaging dataset through the pipeline from start (from 
  dicomTar.pl) -- Ensure entries from the previous attempt to load the dataset
  have been removed from the following database tables:

- `parameter_file`
- `tarchive`
- `mri_acquisition_dates`
- `files` (best to delete from this table last)
- `session` - not recommended - only if necessary, and only if no other data is 
    associated to this session e.g. on the Behavioural side of Loris.

It is also recommended to remove from the tarchive directory the last generated 
  *.tar package for this dataset.

If any Quality Control flags or comments exist for these scans, you may also 
  wish to delete specific records from files_qcstatus and the `mri_feedback_*` 
  tables.

For backing up, re-labelling and re-loading MRI datasets with QC information, 
  see [Beta Tutorial](https://github.com/aces/Loris/wiki/Reloading-MRI-data-for-mislabelled-session)

#### Multiple scanner datasets per session

In cases where a subject was scanned in two scanner sessions within a single 
  study Timepoint, both datasets should be loaded and associated to the same 
  visit label / session table record. Create separate tarchives for each 
  DICOM dataset upload each to the same visit.

### 2.5.3 BrainBrowser Troubleshooting 

- `/data/$PROJ` directory and subdirectories must be readable and executable by 
    the Apache linux user.
- If [showDatabaseQueries](https://github.com/aces/Loris/wiki/Behavioural-Database#showdatabasequeries)
    is enabled, image volumes will not display properly in the Imaging Browser.
- Verify the Configuration module (*Paths*) `MINC files` setting is 
    `/data/$PROJ/data/`.

Feel free to visit the [FAQ](AppendixA-FAQ.md) section for more 
  troubleshooting solutions.

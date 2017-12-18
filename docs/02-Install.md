# 2.0 - Install

## 2.1 Dependencies and installation

Dependencies and installation information are documented on the LORIS-MRI
  [README.md](../README.md) file.


## 2.2 Setup

### 2.2.1 Set up imaging insertion scripts

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
    [bypassing protocol violation checks](AppendixA-FAQ.md#bypassing-protocol-violation-checks)
- To **whitelist/blacklist** specific scan types -- e.g. in case of protocol 
    exclusion, case sensitivity or labelling variance -- modify the subroutine 
    `isFileToBeRegisteredGivenProtocol()` in your prod file 
    (`/data/$PROJ/bin/mri/dicom-archive/.loris_mri/prod`) e.g.:
```
if($acquisitionProtocol eq 't1' or $acquisitionProtocol eq 't2' or $acquisitionProtocol eq 'dti' or $acquisitionProtocol eq 'bold' or $acquisitionProtocol =~ /fmri/) { return 1; }
```

### 2.2.2 Set up the Imaging Uploader module

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

See also: [Logs](AppendixA-FAQ.md#logs) and
  [Troubleshooting Insertion of Uploaded Datasets](AppendixA-FAQ.md#troubleshooting-insertion-of-uploaded-datasets)

For more details on the different possibilities available to run the insertion 
  pipeline, please refer to [05-PipelineOptions](05-PipelineOptions.md).

#### Setting up Imaging AutoLaunch

- To automatically preprocess, validate and insert all uploaded scans into the
    database, set *ImagingUploader Auto-Launch* to "Yes" in the `Config` module, 
    "Study" section.
- For initial setup and configuration, it is recommended to 
    [manually run the imaging pipeline scripts](AppendixA-FAQ.md#post-upload:-pre-processing-and-insertion-into-loris)
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
  to return false. (See also: [Logs](AppendixA-FAQ.md#logs)).
  
### 2.2.3 Queue Manager (optional/recommended)

Installing Sun GridEngine (SGE) is useful for managing the server processing 
  load for all scripts. Use the `Configuration` module setting `isqsub` to tell 
  the pipeline whether a queue manager is installed.

### 2.2.4 Email Notifications

Installing a mail server is recommended, as the LORIS Imaging pipeline by 
  default attempts to send notifications about completed or failed uploads.

### 2.2.5 Visualization: [BrainBrowser](https://brainbrowser.cbrain.mcgill.ca/)

[BrainBrowser](https://brainbrowser.cbrain.mcgill.ca/), a web-enabled viewer for
   real-time exploration of 3D images, comes embedded within LORIS, including 
   a 2D Volume viewer that can overlay 2 acquisitions. A 3D surface viewer 
   can be used for processed surface datasets.
   
See also: [BrainBrowser Troubleshooting](AppendixA-FAQ.md#2.5.3-brainbrowser-troubleshooting)

### 2.2.6 Quality Control within the Imaging Browser

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

## 2.3 Configuration

## 2.4 Pipeline flow

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
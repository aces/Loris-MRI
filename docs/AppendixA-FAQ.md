# Appendix A - FAQ

### A.1 Installation trouble shooting notes

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

### A.2 Verify loaded images and Troubleshooting

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

### A.3 BrainBrowser Troubleshooting

- `/data/$PROJ` directory and subdirectories must be readable and executable by
    the Apache linux user.
- If [showDatabaseQueries](https://github.com/aces/Loris/wiki/Behavioural-Database#showdatabasequeries)
    is enabled, image volumes will not display properly in the Imaging Browser.
- Verify the Configuration module (*Paths*) `MINC files` setting is
    `/data/$PROJ/data/`.

Feel free to visit the [FAQ](AppendixA-FAQ.md) section for more
  troubleshooting solutions.
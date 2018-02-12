# Appendix A - FAQ

### A.1 Installation troubleshooting notes

Key configuration points to verify:

- Depending on your operating system, some dependencies might be missing.
    During initial troubleshooting of the imaging pipeline, note any related
    error messages (e.g. `install_driver(mysql) failed: Can't locate DBD/mysql
   .pm`) and install missing packages as needed (e.g.
   `sudo apt-get install libdbi-perl`, `sudo apt-get install libdbd-mysql-perl`,
    `sudo apt-get install libarchive-zip-perl`).

- If your MINC toolkit is older than 1.9.14 and your scans have no Date of Birth
   value, you may see an age unit error during DICOM to MINC conversion.
   Instructions for compiling a more recent version of the MINC toolkit are 
   available on [MNI-BIC GitHub](https://github.com/BIC-MNI/minc-toolkit-v2).

### A.2 Images display troubleshooting notes

Once an MRI scan session has been successfully inserted, it will be listed in
  the Imaging Browser main data table (also linked from the DICOM Archive
  sub-page: "View Images").

Verify in the Imaging Browser's View Session page that a `jpg` showing 3 slice
  orientations displays properly; if not, verify your permissions and restart
  apache:
```
sudo chmod o+r /data/$PROJ/bin
sudo chmod o+r /data/$PROJ/data
sudo service apache2 restart
```

If download links do not work, ensure that the `/data/$PROJ/data/assembly`
  directory and subdirectories are executable.

### A.3 Logs troubleshooting notes

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

### A.4 Insertion script troubleshooting notes

If upload was successful but issues were encountered with the imaging insertion
  pipeline scripts:

- CentOS: check for additional dependencies/configurations (e.g. DICOM
    Dictionary path) in the detailed
    [CentOS Imaging Installation transcript](https://github.com/aces/Loris/wiki/CentOS-Imaging-installation-transcript)
- Manually re-run the entire pipeline sequence using the 
`imaging_upload_file.pl` script
- If one of the final steps such as the MINC conversion is failing, you may
    wish to just re-run the `tarchiveLoader` script.
- See also [re-running the Imaging pipeline](#rerunning-the-imaging-pipeline)
    section for troubleshooting information.

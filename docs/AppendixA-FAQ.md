# Appendix A - FAQ

This section covers some of the most commonly encountered errors when running 
the insertion scripts. They are divided into 3 separate tables, with each table 
handling errors originating from the LORIS-MRI installation (Table 1), the LORIS 
modules setup (Table 2), or the LORIS-MRI scripts (Table 3).


_**Table 1: Common errors encountered during LORIS-MRI installation, and their proposed solutions.**_

| **Error** | **Cause** | **How to Fix**|
|:------|:------|:----------| 
|`install_driver(mysql) failed: Can't locate DBD/mysql.pm`|Missing dependency|`sudo apt-get install libdbd-mysql-perl`|
|`ERROR: You don't have a configuration file named 'prod' in: /data/%PROJECT%/bin/mri/dicom-archive/.loris_mri/`| Your `environment` file does not contain your actual LORIS-MRI project name. Instead, it contains the placeholder `%PROJECT%` as provided in the 'generic' file and/or your `environment` file is not sourced| Source the environment file located in `/data/$PROJECT/bin/mri/` after making sure that the `$PROJECT` variable is replaced with your LORIS-MRI project name|
|`ERROR: You don't have a configuration file named 'prod' in: /data/loris-MRI/bin/mri/dicom-archive/.loris_mri/` *note*: `loris-MRI` is an example project name used in this illustration| Wrong file and/or directory permissions| Make sure that the `/data/loris-MRI/bin/mri` directory, and all directories within are readable by the user running the scripts (`lorisadmin` or the front-end `apache` user)|
|`ERROR: You don't have a configuration file named 'prod' in: /data/loris-MRI/bin/mri/dicom-archive/.loris_mri/` *note*: `loris-MRI` is an example project name used in this illustration| Syntax error in the `prod` file in the customized routines (for example a missing closing bracket)| Check the routines that were customized for your project needs|
|`DB connection failed`| Database credentials in the `prod` file were entered incorrectly during the install, or they were modified subsequently| Make sure that your `prod` file contains the correct database connection/credentials information in the `DATABASE Settings, Section I`|


_**Table 2: Common errors encountered due to missing LORIS (front-end) module setup steps, and their proposed solutions.**_

| **Error** | **Cause** | **How to Fix**|
|:------|:------|:----------| 
|Images thumbnails do not show up in Imaging Browser. They appear as a broken image icon|Wrong permissions to the `/data/$PROJECT/data/pic/` folder|Ensure that the `apache` user can read/execute the `pic` images folder|
|Images thumbnails do not show up in Imaging Browser. They appear as a broken image icon|Wrong `Images` path under the `Paths` section in LORIS Configuration module|Ensure the path to the images is correct, typically `/data/$PROJECT/data/`|
|4-D images (e.g. DTI, fMRI) in brainbrowser do not show any volumes (Play button not displayed)|Most likely a dcm2mnc conversion error|Post an issue on the [minc-toolkit Github Issues page](https://github.com/BIC-MNI/minc-toolkit/issues)|
|Brainbrowser says `Loading…` but no image shows up|Wrong permissions to the `/data/$PROJECT/data/assembly/` folder|Ensure that the apache user can read/execute the MINC `assembly` images folder|
|Brainbrowser says `Loading…` but no image shows up|Wrong `Images` path under the `Paths` section in LORIS Configuration module|Ensure the path to the MINC images is correct, typically `/data/$PROJECT/data/`| 
|Brainbrowser says `Loading…` but no image shows up|The `config.xml` in LORIS does not have the MINC Toolkit Path set properly|Fill out the path `<MINCToolsPath>` to the MINC Toolkit Installation in the `config.xml` (on the LORIS side). The last trailing `/`in the path is mandatory|


_**Table 3: Common errors encountered during execution of the LORIS-MRi insertion scripts, and their proposed solutions.**_

| **Error** | **Cause** | **How to Fix**|
|:------|:------|:----------| 
|`The Candidate info validation has failed`|PatientName/PatientID header in the DICOMs not anonymized according to the LORIS convention `(PSCID_CandID_VisitLabel)`|Use [DICAT](https://github.com/aces/DICAT) to anonymize it properly OR Use the DICOM toolkit `dcmodify` command. The following one-line command (to be run from the folder where the DICOM files are) which anonymizes your entire folder of DICOM files is: `for i in $(find -type f); do dcmodify -ma PatientName="PSCID_CandID_VisitLabel" -nb $i; done`|
|`The Candidate info validation has failed`|The upload scan contains at least one file that is NOT of type DICOM (.bmp or .pdf are common)|Remove any file in the upload that is not of type DICOM|
|`... error message = 'No space left on device ...'`|The temporary directory where the insertion scripts peform its intermediate steps is full. This directory is set to a default value of `/tmp` as specified in the line `export TMPDIR=/tmp` of the `environment` file |Change the `TMPDIR` path in the environment file to a directory with enough space. A good rule of thumb is to have at least 2-3 times the size of the scan being processed as writable space. This space is usually automatically emptied by the pipeline upon a successful execution|
|`ERROR: This class is designed around the notion of a 'Study'. You can't use it with data from multiple studies.  The following study UIDs were found: '1.3.12.2.1107.66060.300000004' '1.3.12.2.1107.66060.300000007' The dicomTar execution has failed`|The upload contains acquisitions from two scanning sessions|Separate into two separate uploads|
|`Out of memory!` during the execution of `dicomTar.pl`|The Transfer syntax of the uploaded scan is other than Little Endian Explicit (such as Implicit or JPEG lossless)|Use the DICOM toolkit `dcmconv` to convert. An example command that changes the transfer syntax to Little Endian Explicit on all DICOM files within a given folder is: `for i in $(find -type f); do dcmconv --write-xfer-little $i $i; done`|
|`Number of MINC files that will be considered for inserting into the database: 0. No data could be converted into valid MINC files. Localizers will not be considered!`|The upload contains only ‘localizer’ type SeriesDescription|Localizers are not processed by default in Loris|
|My uploaded DICOM study contains 6 modalities but only 5 were inserted. The 6th modality was not converted to MINC, neither inserted into the MRI Violated Scans module. In addition, during insertion, the message `Number of MINC files that will be considered for inserting into the database: 5` is displayed, confirming that only 5 files are considered|The missing modality is probably a `localizer` acquisition. `tarchiveLoader` is specifically 'instructed' to exclude this modality|No action needed. This is the expected behavior of the LORIS-MRI insertion pipeline|
|My uploaded DICOM study contains 6 modalities but only 5 were inserted. The 6th modality was not converted to MINC, neither inserted into the MRI Violated Scans module. In addition, during insertion, the message `Number of MINC files that will be considered for inserting into the database: 5` is displayed, confirming that only 5 files are considered|Probably the DICOM headers have blank SeriesNumber. LORIS-MRI generates MINC files and names them temporarily (in intermediate insertion steps) based on their SeriesNumber, before it proceeds to renaming them once the protocol is identified from the `mri_protocol` table. Having no SeriesNumber defaults to `0`, causing overwrites on the intermediate MINC files generated|Ensure that your DICOM headers include a non-blank SeriesNumber for every acquisition in that specific study|
|`The target directory does not contain a single DICOM file`|Probably the DICOM headers have blank StudyUID. The logic of insertion within LORIS-MRI depends on a StudyUID header|Ensure that your DICOM headers include a non-blank StudyUID header|
|My resting-state fMRI scans are tagged as task fMRI although I have 2 entries in the `mri_protocol` table|The resting-state scan has parameters that match those of the task entry of the `mri_protocol` table, and the task-related entry in the `mri_protocol` table precedes that of the resting-state fMRI|Make sure the `mri_protocol` table has parameters that discern between all the study acquired modalities in an **exclusive** manner (i.e. no two row entries have overlapping parameters across all their columns)|
|`no MINCs inserted`|Possibly all the MINC images are violated scans|Check the details of the image headers (from the MRI Violated Scans module or using `mincheader`) against the `mri_protocol` table entries, and adjust the table protocol parameters accordingly|

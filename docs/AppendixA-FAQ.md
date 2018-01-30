# Appendix A - FAQ

This section covers some of the most commonly encountered errors when running 
the insertion scripts. They are divided into 3 sections depending on whether 
the errors are related to the LORIS-MRI installation, LORIS front-end modules 
setup, or LORIS-MRI scripts.

The user is referred to the [README.md](../README.md) which includes a 
post-installation verification section.

|**Stage**  | **Error** | **Cause** | **How to Fix**|
|:-----:|:------|:------|:----------| 
|**LORIS-MRI install**|`install_driver(mysql) failed: Can't locate DBD/mysql.pm`|Missing dependency|`sudo apt-get install libdbd-mysql-perl`|
|                     |`ERROR: You don't have a configuration file named 'prod' in: /data/%PROJECT%/bin/mri/dicom-archive/.loris_mri/`| `environment` file does not contain the actual LORIS-MRI project name instead of the placeholder `%PROJECT%` in the generic file and/or file not sourced| 1) source the environment file located in `/data/$PROJECT/bin/mri/` after making sure that the `$PROJECT` variable is replaced with your LORIS-MRI project name|
|                     |`ERROR: You don't have a configuration file named 'prod' in: /data/loris-MRI/bin/mri/dicom-archive/.loris_mri/`| file/directories permissions| Make sure that the `/data/$PROJECT/bin/mri` directory and all directories within is readable by the user running the scripts (`lorisadmin` or the front-end `apache` user)|
|                     |`ERROR: You don't have a configuration file named 'prod' in: /data/loris-MRI/bin/mri/dicom-archive/.loris_mri/`| Syntax error in the prod file in the customized routines (for example a missing closing bracket)| Check the routines that were customized for your project needs|
|                     |`DB connection failed`| Database credentials are incorrect | Make sure that your `prod` file contains the correct database connection/credentials information|
|**LORIS Module Setup**|Links to images are broken in imaging browser|Wrong permissions to `/data/$PROJECT/data/pic/`|Ensure that the apache user can read the `pic` images|
|                      |Links to images are broken in imaging browser|Wrong Paths in LORIS Configuration module|Ensure the path to the `pic` images is correct|
|                      |4-D images (e.g. DTI, fMRI) in imaging browser do not show any volumes (volumes = 0)|Most likely a dcm2mnc conversion error|Post an issue on the MincTools github|
|                      |Brainbrowser stays `Loading…` but no image shows up|Wrong permissions to `/data/$PROJECT/data/assembly/`|Ensure that the apache user can read the images|
|                      |Links to images are broken in imaging browser|Wrong Paths in LORIS Configuration module|Ensure the path to the MINC images is correct| 
|                      |Links to images are broken in imaging browser|The `config.xm`l in LORIS does not have the MINC Toolkit` Path set properly|Fill out the path `<MINCToolsPath>` to the MINC Toolkit Installation in the `config.xml` (on the LORIS side). The last trailing `/’`in the path is mandatory|
|                      |4-D images (e.g. DTI, fMRI) in brainbrowser do not show any volumes (Play button not displayed)|Most likely a dcm2mnc conversion error|Post an issue on the MincTools github|
|**Insertion Scripts**|`The Candidate info validation has failed`|PatientName/PatientID header in the DICOMs not anonymized according to the LORIS convention `(PSCID_CandID_VisitLabel)`|Use DiCAT to anonymize it properly OR Use the command line in the DICOM toolkit to do so|
|                     |`The Candidate info validation has failed`|The upload contains at least one file that is NOT of type DICOM (.bmp or .pdf are common)|Remove any file in the upload that is not of type DICOM|
|                     |`ERROR: This class is designed around the notion of a 'Study'.
                        	 You can't use it with data from multiple studies.  
                        The following study UIDs were found:
                        '1.3.12.2.1107.5.2.43.66060.30000018010817270342400000004'
                        '1.3.12.2.1107.5.2.43.66060.30000018011016312906600000007'
                        The dicomTar execution has failed`|The upload contains acquisitions from two scanning sessions|Separate into two separate uploads|
|                     |`Out of memory!`|The Transfer syntax if the uploaded scan is other than Little Endian Explicit (such as Implicit or JPEG lossless)|Use the DICOM toolkit to convert|
|                     |`Number of MINC files that will be considered for inserting into the database: 0. No data could be converted into valid MINC files. Localizers will not be considered!`|The upload contains only ‘localizer’ type SeriesDescription|Localizers are not processed by default in Loris|
|                     |My upload had 6 modalities in the DICOMs and only 5 are inserted; the 6th one has no MINC generated and nothing in the violated scans|Probably the scan is a `localizer` scan. `tarchiveLoader` script is specifically instructed to exclude this modality.|No action needed. This is the expected behavior of the Loris-MRI insertion pipeline|
|                     |My resting state fMRI scans are tagged as task fMRI although I have 2 entries in the mri_protocol|The resting state scan has parameters that match those in the task entry of the mri_protocol table|Make sure the mri_protocol table has parameters that discern between all the study acquired modalities in an exclusive manner (i.e. no two row entries have overlapping parameters across all their columns)|
|                     |`no Mincs inserted`|Possibly all the MINC images are violated scans|Check the images headers details against the mri_protocol entries|




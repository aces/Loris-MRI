# 1.0 - Introduction

### 1.1 What is LORIS-MRI? 

LORIS-MRI comprises the core libraries for loading and inserting imaging 
data in LORIS. 
It is maintained in a separate repository so that it can be installed 
on the file server and separated from the web server.
These documents assume you have some knowledge regarding LORIS and
a functioning installation of the core LORIS codebase. For information 
regarding LORIS itself, please consult the [LORIS wiki][1].

LORIS-MRI is a set of libraries, scripts, and settings responsible for the 
insertion, organization, and archiving of uploaded imaging datasets. 
It expects an uploaded, compressed file containing 
a [DICOM][2] scan session composed of many DICOM files. These DICOM files 
will be archived on the server and then converted to:
- [MINC][3] and (optionally) [NIfTI][4] files when using the dcm2mnc converter 
- [BIDS][5] ([NIfTI][4] and JSON) files when using the dcm2niix converter

Knowledge of these file formats can be helpful, but are not 
necessary for using or installing LORIS-MRI.

LORIS-MRI allows you to easily organize and archive your imaging datasets
and links them with corresponding behavioral data in LORIS. Scans can be viewed 
and quality controlled in the LORIS front end via web browser, facilitating 
collaboration between radiologists, clinicians and researchers.

In addition to the import of DICOM files, it is possible to upload a compressed 
file containing an HRRT PET dataset. 
Note that the HRRT insertion pipeline has been 
developed using datasets produced at the Brain Imaging Center of the Montreal
Neurological Institute. Some modification/customization might be needed for other
HRRT PET scanners as datasets coming from those scanners are not standardized.

### 1.2 How does LORIS-MRI work? 
 
![user_story](images/user_story.png)

LORIS-MRI allows multiple ways to upload scans, but typically, users
upload a compressed (.tgz, .tar.gz, or .zip) DICOM (or HRRT) folder via the Imaging
Uploader module that should be composed of **only** DICOM (or HRRT) files. LORIS 
requires that the uploaded file name follow the naming convention 
`PSCID_CANDID_VISIT-LABEL`. 
In addition, all DICOM/HRRT datasets uploaded via the Imaging Uploader or 
transferred on the LORIS-MRI server must be free of any identifying 
information (*e.g.* patient name). A tool can be provided to the sites to 
facilitate de-identification. Please contact the LORIS team for details.

The LORIS-MRI pipeline starts once the scans are uploaded to the server.
The pipeline can start automatically if the autolaunch configuration is
set, otherwise a back-end administrator can manually run the pipeline. 
These options and scripts are detailed in the 
[Pipeline Triggering Options documentation](05-PipelineLaunchOptions.md). 

Insertion progress can be tracked by the user through the Log Viewer in the
Imaging Uploader module, where descriptive messages can be consulted.
The output of the main key steps in the insertion progress can also be consulted 
through:
 - the LORIS DICOM Archive module for successfully archived DICOM datasets`*` 
 - the Imaging Browser module for MINC or NIfTI files (generated from DICOM or HRRT ECAT7 
files) that pass the study-defined MRI protocol`*`
 - BrainBrowser using 3D or 4D navigation of these MINC or NIfTI files. More details on 
BrainBrowser's capabilities can be found [here.][6]

`*` Please note that all acquisitions are included in the DICOM archival
step. However, specific acquisitions (such as `localizers` or `scouts`) can be
excluded from the steps of the pipeline that start at, and follow the DICOM to
MINC (or DICOM to NIfTI) conversion by specifying them in the `excluded_series_description`
field of the Config module (under the Imaging Pipeline section). Note that
the series descriptions entered in that Config field need to be an exact match
of the series description DICOM field.

### 1.3 LORIS-MRI extension: BIDS data direct insertion (no DICOM files available)

The following BIDS datasets can be imported into LORIS using insertion scripts that
are gathered under the Python directory of the LORIS-MRI repository. The script 
called `bids_import.py` allows the import of datasets that have been
organized in a BIDS structure (see [BIDS specifications][7]). 

Those import scripts were written in `Python` in order to take advantage of the 
already existing [PyBIDS library][8] that reads BIDS structures.

Currently, we support the insertion of:
- MRI datasets organized in a BIDS structure
- Electrophysiology datasets organized in a BIDS structure

Note: electrophysiology datasets are imported in LORIS in a specific set of tables 
illustrated in the image below.
![electrophysio_import](images/EEG_BIDS_diagram.png)



[1]: https://github.com/aces/Loris/wiki 
[2]: http://dicomiseasy.blogspot.ca/2011/10/introduction-to-dicom-chapter-1.html
[3]: https://en.wikibooks.org/wiki/MINC/Introduction 
[4]: https://nifti.nimh.nih.gov/ 
[5]: https://bids.neuroimaging.io/
[6]: https://brainbrowser.cbrain.mcgill.ca/
[7]: https://bids-specification.readthedocs.io/en/stable/
[8]: https://github.com/INCF/pybids

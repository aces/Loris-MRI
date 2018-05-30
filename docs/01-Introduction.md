# 1.0 - Introduction

### 1.1 What is LORIS-MRI? 
LORIS-MRI is the backbone of the imaging component that makes up LORIS.
 It is maintained in a separate repository so that it can be installed
 on the file server and separated from the web server.
These documents assume you have some knowledge regarding LORIS and
a functioning installation. For information regarding LORIS itself,
please consult the [LORIS wiki][1].

LORIS-MRI is a set of libraries responsible for the insertion,
organization, and archival of uploaded imaging datasets.
 It expects an uploaded, compressed file containing
a [DICOM][2] study composed of several DICOM files. These DICOM files
 will be archived on the server and converted to [MINC][3] and (optionally)
[NIfTI][4] files. Knowledge of these file formats can be helpful, but are not 
necessary for using or installing LORIS-MRI.

LORIS-MRI allows you to easily organize and archive your imaging datasets
and links them with
 corresponding behavioral data in LORIS. Scans can be viewed and quality
 controlled through the user's web browser, facilitating collaboration
 between radiologists, clinicians and researchers.

### 1.2 How does LORIS-MRI work?  ![user_story](images/user_story.png)
LORIS-MRI allows multiple ways to upload scans, but typically, users
upload a compressed (.tgz, .tar.gz, or .zip) DICOM folder to Imaging
Uploader.  LORIS requires that the uploaded file name follow the naming
convention PSCID_CANDID_VISIT-LABEL. 
In addition, all DICOM datasets uploaded via the Imaging Uploader or 
transferred on the LORIS-MRI server must be free of any identifying 
information (e.g. patient name). A tool can be provided to the sites to 
facilitate deidentification. Please contact the LORIS team for details.

The LORIS-MRI pipeline starts once the scans are uploaded to the server.
The pipeline can start automatically if the autolaunch configuration is
set, otherwise manual intervention is required by a developer with backend 
access to the server. More details about these options and the scripts
needed to run the pipeline can be found [here](05-PipelineLaunchOptions.md). 

Insertion progress can be tracked by the user through the Log Viewer in 
Imaging Uploader, where descriptive messages can be consulted.
The output of the main key steps in the insertion progress can also be consulted 
through the LORIS DICOM archive module for successfully archived DICOM datasets, 
Imaging Browser for MINC-generated files that pass the study-defined MRI protocol, 
and 3D or 4D navigation of these MINC files in BrainBrowser. More details on the
capabilities of BrainBrowser can be found [here.][5]


[1]: https://github.com/aces/Loris/wiki 
[2]: http://dicomiseasy.blogspot.ca/2011/10/introduction-to-dicom-chapter-1.html
[3]: https://en.wikibooks.org/wiki/MINC/Introduction 
[4]: https://nifti.nimh.nih.gov/ 
[5]: https://brainbrowser.cbrain.mcgill.ca/

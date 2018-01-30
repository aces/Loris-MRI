# 5.0 - Pipeline Launch options

Scans upload into LORIS and insertion pipeline's triggering can be done in a few 
ways depending on each project's needs. The best choice will depend on the study 
workflow and protocol. For example, it will depend on whether data is collected 
retrospectively or prospectively, and/or whether the MRI protocol is harmonized 
across all the sites involved in the study.

The different options available are illustrated in the graph below.

![PipelineLaunchOptions](images/PipelineLaunchOptions.png)

Regardless of how the project chooses to upload scans and trigger the insertion, 
the automated quality control and MRI protocol checks performed by the pipeline 
should remain identical.

It is also worth mentioning that all the options illustrated here assume that 
the candidate and visit are already registered in the LORIS database.


In the next three sub-sections, the three launch options illustrated in the 
figure above will be briefly highlighted and the exact command needed to launch 
the pipeline shown.
Details about the scripts themselves can be found in the [Scripts](04-Scripts.md)
section.
 
## 5.1 Option 1

Triggering the pipeline is done from the `/data/$PROJECT/bin/mri` directory as 
follows:

```
uploadNeuroDB/imaging_upload_file.pl -profile prod -upload_id $UploadIDID /PATH/TO/UPLOAD/PSCID_CandID_VisitLabel_OptionalSuffix.zip -verbose
```

where `$UploadID` is the number corresponding to the `UploadID` column in the 
Imaging Uploader table, and `/PATH/TO/UPLOAD/` is typically the 
`/data/incoming/` directory.

This is a typical option for a project prospectively collecting data with 

1. multiple sites involved, 
2. a designated user per site for collecting scans from the scanner console and 
uploading to LORIS, and 
3. a project's imaging specialist monitoring new uploads, and launching the 
insertion pipeline manually, for every new `UploadID` separately. 

## 5.2 Option 2 

Triggering the pipeline from the `/data/$PROJECT/bin/mri` directory can also be 
achieved as follows: 

```
uploadNeuroDB/imaging_upload_file_cronjob.pl -profile prod -verbose
```
                                
The script `imaging_upload_file_cronjob.pl` does not require a specific 
`$UploadID` as an argument because it automatically cycles through 
I<all new uploads> on which the pipeline has not been triggered yet, and 
launches it. As such, this option is used in similar scenarios as Option 1, 
but with the added advantage of not needing to continuously monitor for new 
uploads (the script can be added to the system's crontab to launch at 
pre-scheduled times, as per the project's requirements).



## 5.3 Option 3

The insertion pipeline can then be triggered using the command:
```
./batch_uploads_imageuploader -profile prod < scans_list.txt >log_batch_imageuploader.txt 2>&1 

```

This is an option that addresses retrospectively collected data where uploading 
hundreds of scans, one scan at a time, using the LORIS Imaging Uploader a 
user-friendly interface is impractical. It is also the option of choice for 
prospective studies that want to benefit from tracking scans through the Imaging 
Uploader while automating the upload and insertion process without a user/GUI 
interface interaction. 

In this case, the scans should be transferred to the LORIS-MRI filesystem (for 
example `/data/incoming/`). In addition, an input text file (such as 
`scans_list.txt`) listing one dataset per line should be provided (see example 
below).

Each line in that text file should include the following information separated 
by spaces:

1. the full path to the zipped DICOM dataset (`.zip`, `.tgz`, `.tar.gz`), 
2. Y or N depending on whether the scan is for a phantom or not, and
3. the patient name following the PSCID_CandID_VisitLabel LORIS convention for 
real candidates. Leave BLANK for phantoms.


Example for two entries/scans to be uploaded (one human subject and one phantom):

```
/data/incoming/PSC0001_123456_V1.tar.gz N PSC0001_123456_V1
/data/incoming/Lego_Phantom_MNI_20140101.zip Y
```



# 5.0 - Pipeline Launch options

Scans upload into LORIS and insertion pipeline's triggering can be done 
in a few ways depending on each project's needs. The best choice will 
depend on whether for example data is collected restrospectively or 
propsectively, or whether the MRI protocol is harmonized across all 
the sites involved in the study.

The different options available are graphically illustrated in the graph below.

![UploadWorkFlow](images/UploadWorkflow.pdf)

Regardless of how the project chooses to upload scans and trigger the insertion, 
the automated quality control and MRI protocol checks performed by the pipeline 
should remain identical.

It is also worth mentioning that all the options illustrated here assume that the 
candidate and visit are already registered in the LORIS database.


In the next three sub-sections, the three launch options illustrated in the figure above 
will be briefly highlighted and the exact command needed to launch the pipeline shown.
Details about the scripts themselves can be found in the section [4 Scripts](04-Scripts.md).
 
## 5.1 Option 1

This is a typical option for a project prospectively collecting data with 

1. multiple sites involved, 
2. a designated user per site for collecting scans from the scanner console and uploading to LORIS, 
and 
3. a project imaging specialist monitoring and launching the insertion pipeline as soon as a 
scan is uploaded. In this case, the launch is done from the `/data/$PROJECT/bin/mri` directory as follows:

```
uploadNeuroDB/imaging_upload_file.pl -profile prod -upload_id $UploadIDID /PATH/TO/UPLOAD/PSCID_CandID_VisitLabel_OptionalSuffix.zip -verbose
```

where `$UploadID` is the number corresponding to the UploadID column in the Imaging Uploader table, and
`/PATH/TO/UPLOAD/` is typically the `/data/incoming/` directory.


## 5.2 Option 2 

This option is used in similar scenarios as Option 1, but with potentially the project
imaging specialist launching the pipeline (manually or through a cron job) at pre-defined 
time intervals (e.g. once a day, or once a week).

```
uploadNeuroDB/imaging_upload_file_cronjob.pl -profile prod -verbose
```


## 5.3 Option 3

This is an option that addresses restrospectively collected data where uploading hundreds 
of scans, one scan at a time is impractical. It is also the option of choice for prospective
studies that want to benefit from tracking scans through the Imaging Uploader while automating
the upload and insertion process without a user/GUI interface interaction. 
In this case, the scans should be transferred to a path such as `/data/incoming/` and a text file
containing a list of the scans, e.g. `scans_list.txt`, where `scans_list.txt` contains one scan 
detail per line (example for 2 entries shown below); and each line (for each scan) consists of 
space delimited 

1. the full path to the DICOM zipped scan, 
2. Y or N depending on whether the scan is for a phantom or not, and
3. patient name following the PSCID_CandID_VisitLabel Loris convention for real candidates 
and left BLANK for phantoms.

An example of uploading 2 entries/scans to be uploaded:
```
/data/incoming/PSC0001_123456_V1.tar.gz N PSC0001_123456_V1
/data/incoming/Lego_Phantom_MNI_20140101.zip Y
```

The insertion pipeline can then be triggered using the command:
```
./batch_uploads_imageuploader -profile prod < scans_list.txt >log_batch_imageuploader.txt 2>&1 

```

# 5.0 - Pipeline Trigger options

Projects have options in Uploading scans onto LORIS and in triggering the 
insertion of the scans into the database. Choices are available to address
different project needs. The best choice will depend on whether for example
data is collected restrospectively or propsectively, or whether the MRI
protocol is harmonized across all the sites involved in the study.

The different options available are graphically illustrated in
![UploadWorkFlow](images/UploadWorkflow.pdf).

Although different options are available to upload and dictate the trigger 
to the launch of the insertion pipeline, the insertion quality control and 
MRI protocol checks are supposed to remain identical.

It is also worth mentioning that all the options illustrated here assume that the 
candidate and visit are already registered in the LORIS database.


In the next three sub-sections, the three launch options illusrtated in Figure 5.1 
will be briefly highlighted and the exact command needed to launch the pipeline shown.
Details about the scripts themselves can be found in the Scripts section.
 
## 5.1 Option 1

This is a typical option for a project prospectively collecting data with a) multiple
sites involved, b) a designated user per site for collecting scans from the scanner 
console and uploading to LORIS, and c) a project imaging specialist monitoring and 
launching the insertion pipeline as soon as  ascan is uploaded. In this case, the 
launch is done from the `/data/$PROJECT/bin/mri` directory as follows:

```
uploadNeuroDB/imaging_upload_file.pl -profile prod -upload_id $ID /PATH/TO/UPLOAD/PSCID_CandID_VisitLabel_OptionalSuffix.zip -verbose
```

where `$ID` is the number corresponding to the UploadID column in the Imaging Uploader table, and
`/PATH/TO/UPLOAD/` is typically the `/data/incoming/` directory.


## 5.2 Option 2
This option is used in similar scenarios as Option 1, but with potentially the project
imaging specialist launching the pipeline (manually or through a cron job) at pre-defined 
time intervals (e.g. once a day, or once a week).

```
uploadNeuroDB/imaging_upload_file_cronjob.pl -profile prod -verbose
```


## 5.3 Option 3
This is an option that addresses restrospecively collected data where uploading hundreds 
os scans, one scan at a time is impractical. It is also the option of choice for prospective
studies that want to benefit from tracking scans through the Imaging Uploader while automating
the upload and insertion process without a user/GUI interface interaction. 
In this case, the scans should be placed in a path such as `/data/incoming/` and a text file
containing a list of the scans, e.g. `scans_list.txt`, where `scans_list.txt` contains one scan 
detail per line (example for 2 entries shown below); and each line (for each scan) consists of 
space delimited 

    1) the full path to the DICOM zipped scan, 
    2) Y or N depending on whether the scan is for a phantom or not, 
    and 3) patient name following the PSCID_CandID_VisitLabel Loris convention for real candidates and left BLANK for phantoms

An example of uploading 2 entries/scans to be uploaded:
```
/data/incoming/PSC0001_123456_V1.tar.gz N PSC0001_123456_V1
/data/incoming/Lego_Phantom_MNI_20140101.zip Y
```

The insertion pipeline can then be triggered using the command:
```
./batch_uploads_imageuploader -profile prod < scans_list.txt >log_batch_imageuploader.txt 2>&1 

```

## 5.4 Option 4 ???????????
This is an option that addresses a possibility of a project wanting to split the insertion 
pipeline into 2 major 


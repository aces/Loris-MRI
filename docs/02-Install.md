# 2.0 - Install

## 2.1 Dependencies

## 2.2 Setup

## 2.3 Configuration

## 2.4 Pipeline flow

The graph below shows the different frontend modules as well as the name
  of the main table used by those modules and the scripts that allows
  insertion in the database of the information displayed within those
  modules.

![pipeline_flow](images/overall_flow.png)

Once a new imaging study has been uploaded via the imaging uploader
  module, several scripts are run (automatically or manually) in order
  to insert the images into LORIS. The sections below describe an
  overview of the insertion pipeline flow.

#### 2.4.1 Upload validation & archive of DICOMs

The very first step of the pipeline flow is to unzip and check whether
  the uploaded study is valid (correct PatientName, ????????).

#### 2.4.2 Archival of the DICOM study

Once the uploaded study has been validated, the
  `imaging_upload_file.pl` will call `dicomTar.pl` to insert the DICOM
  study into the database and archive it in a .tar file.

#### 2.4.3 Insertion of MINC images

After the DICOM study has been archived and inserted into the database
  the `imaging_upload_file.pl` script will call `tarchiveLoader` to


![pipeline_flow](images/pipeline_flow.png)


## 2.5 Common errors

[FAQ](AppendixA-FAQ.md)

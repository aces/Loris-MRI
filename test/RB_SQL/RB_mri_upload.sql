SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE `mri_upload`;
LOCK TABLES `mri_upload` WRITE;
INSERT INTO `mri_upload` (`UploadID`, `UploadedBy`, `UploadDate`, `UploadLocation`, `DecompressedLocation`, `InsertionComplete`, `Inserting`, `PatientName`, `number_of_mincInserted`, `number_of_mincCreated`, `TarchiveID`, `SessionID`, `IsCandidateInfoValidated`, `IsTarchiveValidated`, `IsPhantom`) VALUES (126,'cecile','2024-08-30 14:26:07','/data/incoming/MTL001_300001_V2_t1w.tgz','/data/not_backed_up/ImagingUpload-14-30-FoTt1K',0,0,'MTL001_300001_V2',NULL,NULL,74,NULL,0,0,'N');
INSERT INTO `mri_upload` (`UploadID`, `UploadedBy`, `UploadDate`, `UploadLocation`, `DecompressedLocation`, `InsertionComplete`, `Inserting`, `PatientName`, `number_of_mincInserted`, `number_of_mincCreated`, `TarchiveID`, `SessionID`, `IsCandidateInfoValidated`, `IsTarchiveValidated`, `IsPhantom`) VALUES (127,'cecile','2025-03-18 17:05:25','/data/incoming/OTT203_300203_V3_t1w.tgz','/data/not_backed_up/OTT203_300203_V3_t1w',0,0,'OTT203_300203_V3',NULL,NULL,75,NULL,0,0,'N');
INSERT INTO `mri_upload` (`UploadID`, `UploadedBy`, `UploadDate`, `UploadLocation`, `DecompressedLocation`, `InsertionComplete`, `Inserting`, `PatientName`, `number_of_mincInserted`, `number_of_mincCreated`, `TarchiveID`, `SessionID`, `IsCandidateInfoValidated`, `IsTarchiveValidated`, `IsPhantom`) VALUES (128,'cecile','2025-04-02 16:14:13','/data/incoming/ROM184_400184_V3_for_nifti_insertion.tgz','/data/incoming/dataset_for_tests/ROM184_400184_V3_for_nifti_insertion',0,0,'ROM184_400184_V3',NULL,NULL,76,NULL,1,1,'N');
UNLOCK TABLES;
SET FOREIGN_KEY_CHECKS=1;

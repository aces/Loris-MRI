SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE `mri_upload`;
LOCK TABLES `mri_upload` WRITE;
INSERT INTO `mri_upload` (`UploadID`, `UploadedBy`, `UploadDate`, `UploadLocation`, `DecompressedLocation`, `InsertionComplete`, `Inserting`, `PatientName`, `number_of_mincInserted`, `number_of_mincCreated`, `TarchiveID`, `SessionID`, `IsCandidateInfoValidated`, `IsTarchiveValidated`, `IsPhantom`) VALUES (126,'cecile','2024-08-30 14:26:07','/data/incoming/MTL001_300001_V2_t1w.tgz','/data/not_backed_up/ImagingUpload-14-30-FoTt1K',0,0,'MTL001_300001_V2',NULL,NULL,74,NULL,1,0,'N');
UNLOCK TABLES;
SET FOREIGN_KEY_CHECKS=1;

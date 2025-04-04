SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE `files`;
LOCK TABLES `files` WRITE;
INSERT INTO `files` (`FileID`, `SessionID`, `File`, `SeriesUID`, `EchoTime`, `PhaseEncodingDirection`, `EchoNumber`, `CoordinateSpace`, `OutputType`, `MriScanTypeID`, `FileType`, `InsertedByUserID`, `InsertTime`, `SourcePipeline`, `PipelineDate`, `SourceFileID`, `ProcessProtocolID`, `Caveat`, `TarchiveSource`, `HrrtArchiveID`, `ScannerID`, `AcqOrderPerModality`, `AcquisitionDate`) VALUES (2,564,'assembly_bids/sub-400184/ses-V3/func/sub-400184_ses-V3_task-rest_run-1_bold.nii.gz','1.3.12.2.1107.5.2.32.35412.2012101116562350450995317.0.0.0',0.027,'j-',NULL,'native','native',40,'nii','cecile',1743625152,NULL,NULL,NULL,NULL,0,76,NULL,4,NULL,'2016-08-19');
UNLOCK TABLES;
SET FOREIGN_KEY_CHECKS=1;

SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE `tarchive_series`;
LOCK TABLES `tarchive_series` WRITE;
INSERT INTO `tarchive_series` (`TarchiveSeriesID`, `TarchiveID`, `SeriesNumber`, `SeriesDescription`, `SequenceName`, `EchoTime`, `RepetitionTime`, `InversionTime`, `SliceThickness`, `PhaseEncoding`, `NumberOfFiles`, `SeriesUID`, `Modality`) VALUES (5678,74,2,'t1_mpr_1mm_p2','*tfl3d1_ns',3.16,2400,1200,1,'ROW',224,'1.3.12.2.1107.5.2.32.35045.2015070800014525082741283.0.0.0','MR');
UNLOCK TABLES;
SET FOREIGN_KEY_CHECKS=1;

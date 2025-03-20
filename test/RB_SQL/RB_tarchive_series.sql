SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE `tarchive_series`;
LOCK TABLES `tarchive_series` WRITE;
INSERT INTO `tarchive_series` (`TarchiveSeriesID`, `TarchiveID`, `SeriesNumber`, `SeriesDescription`, `SequenceName`, `EchoTime`, `RepetitionTime`, `InversionTime`, `SliceThickness`, `PhaseEncoding`, `NumberOfFiles`, `SeriesUID`, `Modality`) VALUES (5679,75,2,'t1_mpr_1mm_p2_pos50','*tfl3d1_ns',3.16,2400,1200,1,'ROW',160,'1.3.12.2.1107.5.2.32.35248.2017100418274954307032511.0.0.0','MR');
INSERT INTO `tarchive_series` (`TarchiveSeriesID`, `TarchiveID`, `SeriesNumber`, `SeriesDescription`, `SequenceName`, `EchoTime`, `RepetitionTime`, `InversionTime`, `SliceThickness`, `PhaseEncoding`, `NumberOfFiles`, `SeriesUID`, `Modality`) VALUES (5781,74,1,'localizer','*fl2d1',5,20,NULL,10,'COL',1,'1.3.12.2.1107.5.2.32.35045.2015070723561020366340472.0.0.0','MR');
INSERT INTO `tarchive_series` (`TarchiveSeriesID`, `TarchiveID`, `SeriesNumber`, `SeriesDescription`, `SequenceName`, `EchoTime`, `RepetitionTime`, `InversionTime`, `SliceThickness`, `PhaseEncoding`, `NumberOfFiles`, `SeriesUID`, `Modality`) VALUES (5782,74,2,'t1_mpr_1mm_p2','*tfl3d1_ns',3.16,2400,1200,1,'ROW',224,'1.3.12.2.1107.5.2.32.35045.2015070800014525082741283.0.0.0','MR');
UNLOCK TABLES;
SET FOREIGN_KEY_CHECKS=1;

--
-- Table structure for `bids_file_level_category`
--
DROP TABLE IF EXISTS `bids_export_file_level_category`;
CREATE TABLE `bids_export_file_level_category` (
  `BIDSExportFileLevelCategoryID`   int(10) unsigned NOT NULL AUTO_INCREMENT,
  `BIDSExportFileLevelCategoryName` varchar(12) NOT NULL,
  PRIMARY KEY (`BIDSExportFileLevelCategoryID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO bids_export_file_level_category (BIDSExportFileLevelCategoryName) VALUES
  ('study'),
  ('image'),
  ('session');


--
-- Add necessary file types in ImagingFileTypes
--
INSERT INTO ImagingFileTypes (type, description) VALUES
  ('json',   'JSON file'),
  ('readme', 'README file'),
  ('tsv',    'Tab separated values (TSV) file'),
  ('bval',   'NIfTI DWI file with b-values'),
  ('bvec',   'NIfTI DWI file with b-vectors');


--
-- Create table to store PhaseEncodingDirection possible values
--
DROP TABLE IF EXISTS `bids_phase_encoding_direction`;
CREATE TABLE `bids_phase_encoding_direction` (
  `BIDSPhaseEncodingDirectionID`   int(3) unsigned NOT NULL AUTO_INCREMENT,
  `BIDSPhaseEncodingDirectionName` varchar(3) NOT NULL,
  PRIMARY KEY (`BIDSPhaseEncodingDirectionID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO bids_phase_encoding_direction (BIDSPhaseEncodingDirectionName) VALUES
  ('i'),
  ('i-'),
  ('j'),
  ('j-'),
  ('k'),
  ('k-')
;

--
-- Alter table bids_mri_scan_type_rel to add a PhaseEncodingDirection field
--

ALTER TABLE bids_mri_scan_type_rel ADD COLUMN BIDSPhaseEncodingDirectionID int(3) unsigned DEFAULT NULL;
ALTER TABLE bids_mri_scan_type_rel
    ADD CONSTRAINT `FK_bids_phase_encoding_direction`
        FOREIGN KEY (`BIDSPhaseEncodingDirectionID`)
        REFERENCES `bids_phase_encoding_direction` (`BIDSPhaseEncodingDirectionID`);



--
-- BIDS non-imaging file types
--
DROP TABLE IF EXISTS `bids_export_non_imaging_file_category`;
CREATE TABLE `bids_export_non_imaging_file_category` (
  `BIDSNonImagingFileCategoryID`   int(10) unsigned NOT NULL AUTO_INCREMENT,
  `BIDSNonImagingFileCategoryName` varchar(40) NOT NULL,
  PRIMARY KEY (`BIDSNonImagingFileCategoryID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO bids_export_non_imaging_file_category (BIDSNonImagingFileCategoryName) VALUES
  ('dataset_description'),
  ('README'),
  ('bids-validator-config'),
  ('participants_list_file'),
  ('session_list_of_scans');


--
-- Table structure for table `bids_export_files`
--

DROP TABLE IF EXISTS `bids_export_files`;
CREATE TABLE `bids_export_files` (
  `BIDSExportedFileID`           int(10) unsigned NOT NULL AUTO_INCREMENT,
  `BIDSExportFileLevelID`        int(10) unsigned NOT NULL,
  `FileID`                       int(10) unsigned DEFAULT NULL,
  `SessionID`                    int(10) unsigned DEFAULT NULL,
  `BIDSNonImagingFileCategoryID` int(10) unsigned DEFAULT NULL,
  `BIDSCategoryID`               int(3)  unsigned DEFAULT NULL,
  `FileType`                     varchar(12) NOT NULL,
  `FilePath`                     varchar(255) NOT NULL,
  PRIMARY KEY (`BIDSExportedFileID`),
  CONSTRAINT `FK_bef_BIDSExportFileLevelID`        FOREIGN KEY (`BIDSExportFileLevelID`)        REFERENCES `bids_export_file_level_category` (`BIDSExportFileLevelCategoryID`),
  CONSTRAINT `FK_bef_FileID`                       FOREIGN KEY (`FileID`)                       REFERENCES `files`   (`FileID`),
  CONSTRAINT `FK_bef_SessionID`                    FOREIGN KEY (`SessionID`)                    REFERENCES `session` (`ID`),
  CONSTRAINT `FK_bef_BIDSNonImagingFileCategoryID` FOREIGN KEY (`BIDSNonImagingFileCategoryID`) REFERENCES `bids_export_non_imaging_file_category` (`BIDSNonImagingFileCategoryID`),
  CONSTRAINT `FK_bef_ModalityType`                 FOREIGN KEY (`BIDSCategoryID`)               REFERENCES `bids_category` (`BIDSCategoryID`),
  CONSTRAINT `FK_bef_FileType`                     FOREIGN KEY (`FileType`)                     REFERENCES `ImagingFileTypes` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Insert statements for the DWI acquisitions of RB dataset
--

INSERT INTO bids_scan_type_subcategory SET BIDSScanTypeSubCategory='acq-25-direction';
INSERT INTO bids_scan_type_subcategory SET BIDSScanTypeSubCategory='acq-65-direction';

INSERT INTO bids_mri_scan_type_rel
  (
    MRIScanTypeID,
    BIDSCategoryID,
    BIDSScanTypeID,
    BIDSScanTypeSubCategoryID,
    BIDSEchoNumber
  )
  VALUES
  (
    (SELECT ID FROM mri_scan_type WHERE Scan_type='dwi25'),
    (SELECT BIDSCategoryID FROM bids_category WHERE BIDSCategoryName='dwi'),
    (SELECT BIDSScanTypeID FROM bids_scan_type WHERE BIDSScanType='dwi'),
    (SELECT BIDSScanTypeSubCategoryID FROM bids_scan_type_subcategory WHERE BIDSScanTypeSubCategory='acq-25-direction'),
    NULL
  );

INSERT INTO bids_mri_scan_type_rel
  (
    MRIScanTypeID,
    BIDSCategoryID,
    BIDSScanTypeID,
    BIDSScanTypeSubCategoryID,
    BIDSEchoNumber
  )
  VALUES
  (
    (SELECT ID FROM mri_scan_type WHERE Scan_type='dwi65'),
    (SELECT BIDSCategoryID FROM bids_category WHERE BIDSCategoryName='dwi'),
    (SELECT BIDSScanTypeID FROM bids_scan_type WHERE BIDSScanType='dwi'),
    (SELECT BIDSScanTypeSubCategoryID FROM bids_scan_type_subcategory WHERE BIDSScanTypeSubCategory='acq-65-direction'),
    NULL
  );



SELECT Scan_type, BIDSCategoryName, BIDSScanType, BIDSScanTypeSubCategory, BIDSEchoNumber FROM bids_mri_scan_type_rel bmstr LEFT JOIN bids_category USING(BIDSCategoryID) LEFT JOIN bids_scan_type USING (BIDSScanTypeID) LEFT JOIN bids_scan_type_subcategory USING (BIDSScanTypeSubCategoryID) LEFT JOIN mri_scan_type mst ON mst.ID=bmstr.MRIScanTypeID;


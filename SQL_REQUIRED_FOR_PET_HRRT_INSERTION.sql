-- Create a table that will list all imaging modalities that the imaging
-- uploader can handle
CREATE TABLE `ImagingModality` (
  `ImagingModalityID` INT(11)      NOT NULL AUTO_INCREMENT,
  `Modality`          VARCHAR(255) NOT NULL,
  `Description`       VARCHAR(255) NOT NULL,
  PRIMARY KEY (`ImagingModalityID`),
  UNIQUE KEY  `Name` (`Name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Insert into the ImagingModality 3 supported modality by the imaging uploader
INSERT INTO ImagingModality (Modality, Description) VALUES
  ("MRI DICOM", "MRI DICOM study"),
  ("PET HRRT",  "PET studies using the Siemens HRRT scanner");

-- Alter the mri_upload table to insert FK column linking to ImagingModalityID
ALTER TABLE `mri_upload`
  ADD COLUMN `ImagingModalityID` INT(11),
  ADD CONSTRAINT `fk_ImaingModality`
    FOREIGN KEY (`ImagingModalityID`)
    REFERENCES `ImagingModality` (`ImagingModalityID`);

-- Update the mri_upload table to set all previous uploads to MRI DICOM
UPDATE mri_upload SET
  ImagingModalityID=(SELECT ImagingModalityID
                     FROM ImagingModality
                     WHERE Modality="MRI DICOM");




-- Create the hrrt_archive and hrrt_archive_files tables
CREATE TABLE `hrrt_archive` (
  `HrrtArchiveID`     INT(11)      NOT NULL AUTO_INCREMENT,
  `PatientName`       VARCHAR(255) NOT NULL DEFAULT '',
  `CenterName`        VARCHAR(255) NOT NULL DEFAULT '',
  `CreatingUser`      VARCHAR(255) NOT NULL DEFAULT '',
  `SourceLocation`    VARCHAR(255) NOT NULL DEFAULT '',
  `EcatFileCount`     INT(11)      NOT NULL DEFAULT '0',
  `NonEcatFileCount`  INT(11)      NOT NULL DEFAULT '0',
  `LastUpdate`        DATETIME              DEFAULT NULL,
  `DateAcquired`      DATE                  DEFAULT NULL,
  `DateFirstArchived` DATETIME              DEFAULT NULL,
  `DateLastArchived`  DATETIME              DEFAULT NULL,
  `md5sumArchive`     VARCHAR(255)          DEFAULT NULL,
  `ArchiveLocation`   VARCHAR(255)          DEFAULT NULL,
  `SessionID`         INT(10) unsigned      DEFAULT NULL,
  `CreateInfo`        TEXT,
  PRIMARY KEY (`HrrtArchiveID`),
  KEY `patNam` (`CenterName`(10),`PatientName`(30)),
  KEY `FK_hrrt_archive_sessionID` (`SessionID`),
  CONSTRAINT `FK_hrrt_archive_sessionID`
    FOREIGN KEY (`SessionID`)
    REFERENCES `session` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


CREATE TABLE `hrrt_archive_files` (
  `HrrtArchiveFileID` INT(11)      NOT NULL AUTO_INCREMENT,
  `HrrtArchiveID`     INT(11)      NOT NULL DEFAULT '0',
  `Md5Sum`            VARCHAR(255) NOT NULL,
  `FileName`          VARCHAR(255) NOT NULL,
  PRIMARY KEY (`HrrtArchiveFileID`),
  KEY `HrrtArchiveID` (`HrrtArchiveID`),
  CONSTRAINT `hrrt_archive_files_ibfk_1`
    FOREIGN KEY (`HrrtArchiveID`)
    REFERENCES  `hrrt_archive` (`HrrtArchiveID`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;



-- Create the mri_upload_rel table
CREATE TABLE `mri_upload_rel` (
  `UploadRelID`   INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  `UploadID`      INT(10) UNSIGNED NOT NULL,
  `HrrtArchiveID` INT(11) DEFAULT NULL,
  PRIMARY KEY (`UploadRelID`),
  KEY `FK_mriuploadrel_UploadID` (`UploadID`),
  KEY `FK_mriuploadrel_HrrtArchiveID` (`HrrtArchiveID`),
  CONSTRAINT `FK_mriuploadrel_UploadID`
    FOREIGN KEY (`UploadID`)
    REFERENCES `mri_upload` (`UploadID`),
  CONSTRAINT `FK_mriuploadrel_HrrtArchiveID`
    FOREIGN KEY (`HrrtArchiveID`)
    REFERENCES `hrrt_archive` (`HrrtArchiveID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
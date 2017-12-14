-- 
-- Table structure for table `tarchive`
-- 

CREATE TABLE tarchive (
  TarchiveID int(11) AUTO_INCREMENT NOT NULL,
  DicomArchiveID varchar(255) NOT NULL default '',
  PatientID varchar(255) NOT NULL default '',
  PatientName varchar(255) NOT NULL default '',
  PatientDoB date NOT NULL default '0000-00-00',
  PatientGender varchar(255) default NULL,
  neurodbCenterName varchar(255) default NULL,
  CenterName varchar(255) NOT NULL default '',
  LastUpdate datetime NOT NULL default '0000-00-00 00:00:00',
  DateAcquired date NOT NULL default '0000-00-00',
  DateFirstArchived datetime default NULL,
  DateLastArchived datetime default NULL,
  AcquisitionCount int(11) NOT NULL default '0',
  NonDicomFileCount int(11) NOT NULL default '0',
  DicomFileCount int(11) NOT NULL default '0',
  md5sumDicomOnly varchar(255) default NULL,
  md5sumArchive varchar(255) default NULL,
  CreatingUser varchar(255) NOT NULL default '',
  sumTypeVersion tinyint(4) NOT NULL default '0',
  tarTypeVersion tinyint(4) default NULL,
  SourceLocation varchar(255) NOT NULL default '',
  ArchiveLocation varchar(255) default NULL,
  ScannerManufacturer varchar(255) NOT NULL default '',
  ScannerModel varchar(255) NOT NULL default '',
  ScannerSerialNumber varchar(255) NOT NULL default '',
  ScannerSoftwareVersion varchar(255) NOT NULL default '',
  SessionID int(10) unsigned default NULL,
  uploadAttempt tinyint(4) NOT NULL default '0',
  CreateInfo text,
  AcquisitionMetadata longtext NOT NULL,
  PRIMARY KEY  (TarchiveID),
  UNIQUE KEY `archiveID` (DicomArchiveID)
) TYPE=MyISAM;


-- 
-- Table structure for table `tarchive_series`
-- 

CREATE TABLE tarchive_series (
  TarchiveSeriesID int(11) AUTO_INCREMENT NOT NULL,
  TarchiveID int(11) NOT NULL default 0,
  SeriesNumber int(11) NOT NULL default 0,
  SeriesDescription varchar(255) default NULL,
  SequenceName varchar(255) default NULL,
  EchoTime double default NULL,
  RepetitionTime double default NULL,
  InversionTime double default NULL,
  SliceThickness double default NULL,
  PhaseEncoding varchar(255) default NULL,
  NumberOfFiles int(11) NOT NULL default 0,
  SeriesUID varchar(255) default NULL,
  PRIMARY KEY (TarchiveSeriesID)
);


-- 
-- Table structure for table `tarchive_files`
-- 

CREATE TABLE tarchive_files (
  TarchiveFileID int(11) AUTO_INCREMENT NOT NULL,
  TarchiveID int(11) NOT NULL default 0,
  SeriesNumber int(11) default NULL,
  FileNumber int(11) default NULL,
  EchoNumber int(11) default NULL,
  SeriesDescription varchar(255) default NULL,
  Md5Sum varchar(255) NOT NULL,
  FileName varchar(255) NOT NULL,  /* relative path within tar */
  PRIMARY KEY (TarchiveFileID)
);



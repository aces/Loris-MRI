# ************************************************************
# Sequel Pro SQL dump
# Version 5446
#
# https://www.sequelpro.com/
# https://github.com/sequelpro/sequelpro
#
# Host: localhost (MySQL 5.7.20)
# Database: C-BIGR_MRI_tables
# Generation Time: 2021-01-14 19:13:20 +0000
# ************************************************************


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
SET NAMES utf8mb4;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


# Dump of table bids_category
# ------------------------------------------------------------

DROP TABLE IF EXISTS `bids_category`;

CREATE TABLE `bids_category` (
  `BIDSCategoryID` int(3) unsigned NOT NULL AUTO_INCREMENT,
  `BIDSCategoryName` varchar(10) NOT NULL,
  PRIMARY KEY (`BIDSCategoryID`),
  UNIQUE KEY `BIDSCategoryName` (`BIDSCategoryName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `bids_category` WRITE;
/*!40000 ALTER TABLE `bids_category` DISABLE KEYS */;

INSERT INTO `bids_category` (`BIDSCategoryID`, `BIDSCategoryName`)
VALUES
	(1,'anat'),
	(3,'dwi'),
	(4,'fmap'),
	(2,'func');

/*!40000 ALTER TABLE `bids_category` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table bids_mri_scan_type_rel
# ------------------------------------------------------------

DROP TABLE IF EXISTS `bids_mri_scan_type_rel`;

CREATE TABLE `bids_mri_scan_type_rel` (
  `MRIScanTypeID` int(10) unsigned NOT NULL,
  `BIDSCategoryID` int(3) unsigned DEFAULT NULL,
  `BIDSScanTypeSubCategoryID` int(3) unsigned DEFAULT NULL,
  `BIDSScanTypeID` int(3) unsigned DEFAULT NULL,
  `BIDSEchoNumber` int(3) unsigned DEFAULT NULL,
  PRIMARY KEY (`MRIScanTypeID`),
  KEY `FK_bids_mri_scan_type_rel` (`MRIScanTypeID`),
  KEY `FK_bids_category` (`BIDSCategoryID`),
  KEY `FK_bids_scan_type_subcategory` (`BIDSScanTypeSubCategoryID`),
  KEY `FK_bids_scan_type` (`BIDSScanTypeID`),
  CONSTRAINT `FK_bids_category` FOREIGN KEY (`BIDSCategoryID`) REFERENCES `bids_category` (`BIDSCategoryID`),
  CONSTRAINT `FK_bids_mri_scan_type_rel` FOREIGN KEY (`MRIScanTypeID`) REFERENCES `mri_scan_type` (`ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_bids_scan_type` FOREIGN KEY (`BIDSScanTypeID`) REFERENCES `bids_scan_type` (`BIDSScanTypeID`),
  CONSTRAINT `FK_bids_scan_type_subcategory` FOREIGN KEY (`BIDSScanTypeSubCategoryID`) REFERENCES `bids_scan_type_subcategory` (`BIDSScanTypeSubCategoryID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `bids_mri_scan_type_rel` WRITE;
/*!40000 ALTER TABLE `bids_mri_scan_type_rel` DISABLE KEYS */;

INSERT INTO `bids_mri_scan_type_rel` (`MRIScanTypeID`, `BIDSCategoryID`, `BIDSScanTypeSubCategoryID`, `BIDSScanTypeID`, `BIDSEchoNumber`)
VALUES
	(1015,1,7,7,NULL),
	(1018,3,NULL,5,NULL),
	(1021,3,4,5,NULL),
	(1024,3,5,5,NULL),
	(1027,2,1,1,NULL),
	(1030,2,2,1,NULL),
	(1033,2,3,1,NULL),
	(1039,4,NULL,9,NULL),
	(1042,1,7,7,1),
	(1045,1,7,7,2),
	(1048,1,7,7,3),
	(1051,1,7,7,4),
	(1054,1,7,7,5),
	(1057,1,7,7,6),
	(1060,1,7,7,7),
	(1063,1,7,7,8),
	(1066,1,7,7,9),
	(1069,1,7,7,10),
	(1075,1,6,7,8),
	(1078,1,6,7,9),
	(1081,1,NULL,2,NULL),
	(1084,1,6,7,10),
	(1087,1,NULL,3,NULL),
	(1090,1,NULL,6,1),
	(1093,1,6,7,2),
	(1096,1,6,7,5),
	(1099,1,6,7,7),
	(1100,1,6,7,6),
	(1101,1,6,7,1),
	(1102,1,6,7,NULL),
	(1105,1,NULL,6,2),
	(1107,1,6,7,4),
	(1108,1,6,7,3),
	(1114,4,NULL,8,NULL);

/*!40000 ALTER TABLE `bids_mri_scan_type_rel` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table bids_scan_type
# ------------------------------------------------------------

DROP TABLE IF EXISTS `bids_scan_type`;

CREATE TABLE `bids_scan_type` (
  `BIDSScanTypeID` int(3) unsigned NOT NULL AUTO_INCREMENT,
  `BIDSScanType` varchar(100) NOT NULL,
  PRIMARY KEY (`BIDSScanTypeID`),
  UNIQUE KEY `BIDSScanType` (`BIDSScanType`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `bids_scan_type` WRITE;
/*!40000 ALTER TABLE `bids_scan_type` DISABLE KEYS */;

INSERT INTO `bids_scan_type` (`BIDSScanTypeID`, `BIDSScanType`)
VALUES
	(1,'bold'),
	(5,'dwi'),
	(2,'FLAIR'),
	(8,'magnitude'),
	(6,'PDT2'),
	(9,'phasediff'),
	(3,'T1w'),
	(7,'T2star'),
	(4,'T2w');

/*!40000 ALTER TABLE `bids_scan_type` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table bids_scan_type_subcategory
# ------------------------------------------------------------

DROP TABLE IF EXISTS `bids_scan_type_subcategory`;

CREATE TABLE `bids_scan_type_subcategory` (
  `BIDSScanTypeSubCategoryID` int(3) unsigned NOT NULL AUTO_INCREMENT,
  `BIDSScanTypeSubCategory` varchar(100) NOT NULL,
  PRIMARY KEY (`BIDSScanTypeSubCategoryID`),
  UNIQUE KEY `BIDSScanTypeSubCategory` (`BIDSScanTypeSubCategory`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `bids_scan_type_subcategory` WRITE;
/*!40000 ALTER TABLE `bids_scan_type_subcategory` DISABLE KEYS */;

INSERT INTO `bids_scan_type_subcategory` (`BIDSScanTypeSubCategoryID`, `BIDSScanTypeSubCategory`)
VALUES
	(4,'dir-AP'),
	(5,'dir-PA'),
	(6,'part-mag'),
	(7,'part-phase'),
	(1,'task-rest'),
	(2,'task-rest_dir-AP'),
	(3,'task-rest_dir-PA');

/*!40000 ALTER TABLE `bids_scan_type_subcategory` ENABLE KEYS */;
UNLOCK TABLES;



/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;

# ************************************************************
# Sequel Pro SQL dump
# Version 5446
#
# https://www.sequelpro.com/
# https://github.com/sequelpro/sequelpro
#
# Host: localhost (MySQL 5.7.20)
# Database: open_preventad
# Generation Time: 2021-01-14 16:07:04 +0000
# ************************************************************


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
SET NAMES utf8mb4;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


# Dump of table bids_export_files
# ------------------------------------------------------------

DROP TABLE IF EXISTS `bids_export_files`;

CREATE TABLE `bids_export_files` (
  `BIDSExportedFileID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `FileID` int(10) unsigned DEFAULT NULL,
  `BIDSFileLevel` varchar(12) NOT NULL,
  `FileType` varchar(12) NOT NULL,
  `FilePath` varchar(255) NOT NULL,
  `ModalityType` varchar(12) DEFAULT NULL,
  `BehaviouralType` varchar(30) DEFAULT NULL,
  `SessionID` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`BIDSExportedFileID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;



# Dump of table bids_export_level_types
# ------------------------------------------------------------

DROP TABLE IF EXISTS `bids_export_level_types`;

CREATE TABLE `bids_export_level_types` (
  `BIDSFileLevel` varchar(12) NOT NULL,
  `Description` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`BIDSFileLevel`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `bids_export_level_types` WRITE;
/*!40000 ALTER TABLE `bids_export_level_types` DISABLE KEYS */;

INSERT INTO `bids_export_level_types` (`BIDSFileLevel`, `Description`)
VALUES
	('image','image-level file'),
	('session','session-level file'),
	('study','study-level file');

/*!40000 ALTER TABLE `bids_export_level_types` ENABLE KEYS */;
UNLOCK TABLES;



/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;

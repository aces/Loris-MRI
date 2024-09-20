-- This file contains a few statements to adapt a core LORIS database to LORIS-MRI.
-- This file is ran by the installation or the database dockerfile, it usually
-- should not be ran as a standalone.

-- The script arguments must be set as SQL variables when calling the script.
-- @email     -- User email address
-- @project   -- Project name
-- @minc_dir  -- MINC Toolkit directory

UPDATE Config SET Value = @email
  WHERE ConfigID = (SELECT ID FROM ConfigSettings WHERE Name = 'mail_user');
UPDATE Config SET Value = @project
  WHERE ConfigID = (SELECT ID FROM ConfigSettings WHERE Name = 'prefix');
UPDATE Config SET Value = @minc_dir
  WHERE ConfigID = (SELECT ID FROM ConfigSettings WHERE Name = 'MINCToolsPath');
UPDATE Config SET Value = CONCAT('/data/', @project, '/data/')
  WHERE ConfigID = (SELECT ID FROM ConfigSettings WHERE Name = 'dataDirBasepath');
UPDATE Config SET Value = CONCAT('/data/', @project, '/data/')
  WHERE ConfigID = (SELECT ID FROM ConfigSettings WHERE Name = 'imagePath');
UPDATE Config SET Value = CONCAT('/data/', @project, '/data/tarchive/')
  WHERE ConfigID = (SELECT ID FROM ConfigSettings WHERE Name = 'tarchiveLibraryDir');
UPDATE Config SET Value = CONCAT('/opt/', @project, '/bin/mri/dicom-archive/get_dicom_info.pl')
  WHERE ConfigID = (SELECT ID FROM ConfigSettings WHERE Name = 'get_dicom_info');
UPDATE Config SET Value = CONCAT('/opt/', @project, '/bin/mri/')
  WHERE ConfigID = (SELECT ID FROM ConfigSettings WHERE Name = 'MRICodePath');

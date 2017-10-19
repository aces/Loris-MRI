-- Create a BIDS category that determines the directory in which each nii file from each scan type will be housed 
ALTER TABLE mri_scan_type ADD COLUMN `BIDS_category` enum('anat','func','dwi','fmap') DEFAULT NULL;

-- Now affiliate the specific scan types to their BIDS category
-- CCNA EXAMPLE
UPDATE mri_scan_type SET BIDS_category = 'anat' where Scan_type = '3d_t1w'; 
UPDATE mri_scan_type SET BIDS_category = 'anat' where Scan_type = '2d_flair'; 
UPDATE mri_scan_type SET BIDS_category = 'anat' where Scan_type = 't2_star'; 
UPDATE mri_scan_type SET BIDS_category = 'anat' where Scan_type = 'dual_pd'; 
UPDATE mri_scan_type SET BIDS_category = 'anat' where Scan_type = 'dual_t2'; 
UPDATE mri_scan_type SET BIDS_category = 'func' where Scan_type = 'resting_state'; 
UPDATE mri_scan_type SET BIDS_category = 'func' where Scan_type = 'fmri_epi'; 
UPDATE mri_scan_type SET BIDS_category = 'dwi' where Scan_type = 'dti'; 
UPDATE mri_scan_type SET BIDS_category = 'dwi' where Scan_type = 'b0_map'; 
UPDATE mri_scan_type SET BIDS_category = 'fmap' where Scan_type = 'gre_field_map1'; 
UPDATE mri_scan_type SET BIDS_category = 'fmap' where Scan_type = 'gre_field_map2'; 

-- The Scan_type nomenclature for existing projects might not be BIDS compliant, create the BIDS compliant version; 
ALTER TABLE mri_scan_type ADD COLUMN `BIDS_Scan_type` text NOT NULL;
-- Make the default that used by the project already in Scan_type
UPDATE mri_scan_type SET BIDS_Scan_type = Scan_type;

-- Now make the Scan_type name BIDS compliant
-- CCNA EXAMPLE
UPDATE mri_scan_type SET BIDS_Scan_type = 'T1w' where Scan_type = '3d_t1w'; 
UPDATE mri_scan_type SET BIDS_Scan_type = 'FLAIR' where Scan_type = '2d_flair'; 
UPDATE mri_scan_type SET BIDS_Scan_type = 'T2star' where Scan_type = 't2_star'; 
UPDATE mri_scan_type SET BIDS_Scan_type = 'dualPD' where Scan_type = 'dual_pd'; 
UPDATE mri_scan_type SET BIDS_Scan_type = 'dualT2' where Scan_type = 'dual_t2'; 
UPDATE mri_scan_type SET BIDS_Scan_type = 'rest' where Scan_type = 'resting_state'; 
UPDATE mri_scan_type SET BIDS_Scan_type = 'dwi' where Scan_type = 'dti'; 
UPDATE mri_scan_type SET BIDS_Scan_type = 'b0map' where Scan_type = 'b0_map'; 

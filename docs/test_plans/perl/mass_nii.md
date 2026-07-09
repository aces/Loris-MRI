# Test plan for `mass_nii.pl`

## Manual tests

- If not already done, source the environment file: `source /opt/Loris-MRI/bin/mri/environment`

- run `mass_nii.pl -help` and ensure the help for the script gets printed

- remove NIfTI images for UploadID 106 (linked to TarchiveID 56)
     - remove pics from the filesystem using `rm /data/Loris-MRI/data/assembly/400168/V2/mri/native/*nii  /data/Loris-MRI/data/assembly/400168/V2/mri/native/*bval  /data/Loris-MRI/data/assembly/400168/V2/mri/native/*bvec`
     - in MySQL run the following query to delete path to pic images in `parameter_file`: `DELETE parameter_file FROM parameter_file JOIN files USING (FileID) WHERE TarchiveSource=56 AND Value like "%nii";` (should delete 5 rows)
     - check that the following query returns no results: `SELECT FileID, Value FROM parameter_file JOIN files USING (FileID) WHERE TarchiveSource=56 AND Value like "%nii";`
     - go to the imaging browser for CandID 400168 V2 and check that the buttons "download NIfTI" does not show up anymore under the image's screenshot"

- run `mass_nii.pl` on `FileIDs` `335` to `339`: `mass_nii.pl -profile prod -minFileID 335 -maxFileID 339` 
     - check that the "download NIfTI" button shows up again below the images' screenshots.
     - check that the following query returns 5 rows: `SELECT FileID, Value FROM parameter_file JOIN files USING (FileID) WHERE TarchiveSource=56 AND Value like "%nii.gz";` 
     - check that files with extension ".nii" or ".nii.gz" have been created under `/data/Loris-MRI/data/assembly/400168//V2/mri/native/`

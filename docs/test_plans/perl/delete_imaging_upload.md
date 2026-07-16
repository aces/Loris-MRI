# Test plan for `delete_imaging_upload.pl`

## Manual tests

- [ ] Test deletion of an entire MRI upload (UploadID) with SQL and file backup (ensure the SQL and file backup repopulate the database correctly after the deletion)
- [ ] Test deletion of an UploadID that has the same TarchiveID as an other UploadID - this should fail with an error message explaining there are multiple UploadID for a given TarchiveID
- [ ] Test deletion of an UploadID with QC information attached - this should fail with proper error message
- [ ] Test deletion of an UploadID with a parameter_form filled and the option `-form` and ensure the entries in the parameter form have been deleted
- [ ] On a defaced dataset, test running the delete script with the `-defaced` option - this should delete only non-defaced MINC files for that UploadID
- [ ] Run the delete script with option `-basename <FileBaseName>` specifying a basename for the MINC files to be deleted - only images matching that basename should be deleted for the UploadID


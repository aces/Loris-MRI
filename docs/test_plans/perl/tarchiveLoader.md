# Test plan for `tarchiveLoader.md`

## Manual tests

- [ ] Check that -uploadID, -profile and an existing tarchive are mandatory script argument.
- [ ] Ensure passing an invalid upload ID yields an error.
- [ ] Ensure passing an invalid tarchive (e.g csv file) yields an error.
- [ ] Check that if config setting get_dicom_info is not properly set, tarchiveLoader issues an error that the get_dicom_info command could not be run.
- [ ]  Pick an archive that's already been successfully processed and find its associated upload ID. Run tarchiveLoader using this archive but use option -upload_id with an argument that is not its actual upload ID. Check that you get an error message that the archive and upload ID don't match.
- [ ] Pick an archive that's already been successfully processed and find its associated upload ID. Run tarchiveLoader using this archive and option -upload_id with an argument that is its actual upload ID. Ensure that no minc files are inserted and you get an error message regarding duplicate md5sum for each scan that was originally inserted when the archive was processed.
- [ ] Ensure that config setting default_project is not set and that your prod file does not define any PSCID, visitLabel and ProjectID in function getSubjectIDs. Run tarchiveLoader with a matching tarchive and upload ID and ensure that you get an error message saying that config setting default_project has to be set.


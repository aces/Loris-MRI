test the following scripts:

- [ ] `imaging_upload_file.pl`
- [ ] `imaging_upload_file_cronjob.pl`
- [ ] Test command line arguments: presence/absence/invalid. Make sure the results make sense
- [ ] Basic use case: insert a valid archive.
- [ ] Try to insert an archive with a StudyInstanceUID: ensure you can an error
- [ ] Try to insert an archive containing multiple study instance UID: ensure you get an error
- [ ] Try to insert an archive for which the DICOM header patient name does not match what is in table mri_upload for that upload: ensure you get an error
- [ ] Set config setting lookupCenterNameUsing to something other than PatientID or PatientName. Make sure you get an error.
- [ ] Try to insert an archive that contains valid DICOM files and some text files. Ensure the text files are ignored.


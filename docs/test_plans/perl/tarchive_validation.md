# Test plan for `tarchive_validation.pl`

- [ ] If not already done, source the `environment` file: `source /opt/Loris-MRI/bin/mri/environment`
- [ ] run `tarchive_validation.pl -help` and ensure the help for the script gets printed
- [ ] run the `tarchive_validation.pl` script on a valid archive (example UploadID 106)
```
tarchive_validation.pl -profile prod -uploadID 106 /data/Loris-MRI/data/tarchive/2016/DCM_2016-08-19_ImagingUpload-18-26-C4Y94V.tar
```
- [ ] test `tarchive_validation.pl` script on an invalid archive (example UploadID 109)
    - [ ] delete file `/data/Loris-MRI/data/tarchive/2016/DCM_2016-08-15_ImagingUpload-18-34-hhQQY5.tar` 
    - [ ] recreate the file with `touch` command `touch /data/Loris-MRI/data/tarchive/2016/DCM_2016-08-15_ImagingUpload-18-34-hhQQY5.tar`
    - [ ] run `tarchive_validation.pl -profile prod -uploadID 109 /data/Loris-MRI/data/tarchive/2016/DCM_2016-08-15_ImagingUpload-18-34-hhQQY5.tar` => this should fail with proper message due to different md5

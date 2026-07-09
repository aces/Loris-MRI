# Test plan for `run_dicom_archive_validation.py`

## Manual tests

- If not already done, source the environment file: `source /opt/Loris-MRI/bin/mri/environment`
- run `run_dicom_archive_validation.py -h`
     => should print the help of the script. Make sure the help documentation is up-to-date.
- Bonus points: verify that the automated tests are still implemented

## Automated tests already implemented

- test missing upload ID argument
- test missing tarchive path argument
- test invalid argument
- test invalid upload ID
- test invalid tarchive path
- test mixed up upload ID and tarchive path
- test successful validation

# Test plan for `run_nifti_insertion.py`

## Manual tests

- If not already done, source the environment file: `source /opt/Loris-MRI/bin/mri/environment`
- run `run_nifti_insertion.py -h`
     => should print the help of the script. Make sure the help documentation is up-to-date.
- Bonus points: verify that the automated tests are still implemented

## Automated tests already implemented

- test invalid argument
- test missing NIfTI path argument
- test invalid NIfTI path
- test missing upload ID or tarchive path argument (one of them should be set)
- test missing JSON path argument
- test invalid JSON path
- test invalid upload ID
- test invalid tarchive path
- test tarchive path and upload ID argument provided (only one should be set)
- test NIfTI and tarchive `PatientName` differ
- test NIfTI already inserted
- test NIfTI MRI protocol violated scans features
- test NIfTI MRI violations log exclude features
- test DWI insertion with MRI violations warning
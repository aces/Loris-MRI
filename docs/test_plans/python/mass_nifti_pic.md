# Test plan for `mass_nifti_pic.py`

## Manual tests

- If not already done, source the environment file: `source /opt/Loris-MRI/bin/mri/environment`
- run `mass_nifti_pic.py -h`
     => should print the help of the script. Make sure the help documentation is up-to-date.
- Bonus points: verify that the automated tests are still implemented

## Automated tests already implemented

- test invalid profile
- test smallest `FileID` bigger than largest `FileID`
- test invalid FileID provided
- test on a FileID that already has a pic
- test force option
- test running on a text file
- test successful run

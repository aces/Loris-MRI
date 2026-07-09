# Test plan for `run_dicom_archive_validation.py`

## Manual tests

- If not already done, source the environment file: `source /opt/Loris-MRI/bin/mri/environment`
- run `run_push_imaging_files_to_s3_pipeline.py -h`
     => should print the help of the script. Make sure the help documentation is up-to-date.
- run `run_push_imaging_files_to_s3_pipeline.py -p config.py -u <UPLOAD ID>` on a valid Upload ID and 
  ensure the files has been properly pushed to the S3 bucket
- run `run_push_imaging_files_to_s3_pipeline.py -p config.py` without the `-u` 
     => should print `[ERROR   ] argument --upload_id is required`
- run `run_push_imaging_files_to_s3_pipeline.py -p config.py -u <UPLOAD ID>` on an invalid Upload ID 
     => should print `[ERROR   ] Did not find an entry in mri_upload associated with 'UploadID' 1666`
- run `run_push_imaging_files_to_s3_pipeline.py -p config.py -u <UPLOAD ID>` with the S3 config settings not set in `config.py`
- run `run_push_imaging_files_to_s3_pipeline.py -p config.py -u <UPLOAD ID>` with incorrect S3 authentication settings  in `config.py`
- run `run_push_imaging_files_to_s3_pipeline.py -p config.py -u <UPLOAD ID>` with the incorrect S3 bucket name in `config.py`


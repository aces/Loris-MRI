import os
import subprocess

from lib.db.query.mri_upload import get_mri_upload_with_patient_name
from tests.util.database import get_integration_database_session


def test():
    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_loader.py',
        '--profile', 'database_config.py',
        '--tarchive_path', '/data/loris/tarchive/DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar',
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Check that the return code and standard error are correct
    assert process.returncode == 0
    assert process.stderr == b''

    # Check that the expected file has been created
    assert os.path.exists('/data/loris/assembly_bids/sub-300001')

    # Check that the expected data has been inserted in the database
    db = get_integration_database_session()
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.session is not None
    assert len(mri_upload.session.files) == 1

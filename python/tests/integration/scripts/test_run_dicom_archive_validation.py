import subprocess

from lib.db.queries.config import set_config_with_setting_name
from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from tests.util.database import get_integration_database_session
from tests.util.file_system import check_file_tree


def test():
    
    test_missing_upload_id_arg()

def test_missing_upload_id_arg():
    db = get_integration_database_session()

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--tarchive_path', '/data/loris/tarchive/DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar',
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Check that the return code and standard error are correct
    assert process.returncode == 3
    assert process.stderr.startswith(b'[ERROR   ] argument --upload_id is required')

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None
    assert len(mri_upload.session.files) == 1
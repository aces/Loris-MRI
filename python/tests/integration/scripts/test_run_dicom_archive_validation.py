import subprocess

from sqlalchemy.orm import Session as Database

from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from lib.exitcode import MISSING_ARG
from tests.util.database import get_integration_database_session


def reset_mri_upload_before_running(db: Database):

    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    mri_upload.is_candidate_info_validated = False
    mri_upload.is_dicom_archive_validated = False
    mri_upload.session_id = None
    mri_upload.number_of_minc_inserted = None
    mri_upload.number_of_minc_inserted = None


def check_error_code_and_process_errors(
        process: subprocess.CompletedProcess,
        expected_error_code: int,
        expected_error_message: str
):
    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Isolate STDOUT message and check that it contains the expected error message
    error_msg_is_valid = True if expected_error_message in process.stdout.decode() else False
    assert error_msg_is_valid is True

    # Check that the return code and standard error are correct
    assert process.returncode == expected_error_code
    assert process.stderr == b''


def test_missing_upload_id_arg():
    db = get_integration_database_session()

    # Set some tarchive fields
    reset_mri_upload_before_running(db)

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--tarchive_path', '/data/loris/tarchive/DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar',
    ], capture_output=True)

    # Check error code, error message returned and STDERR - will also print out STDERR and STDOUT
    check_error_code_and_process_errors(
        process,
        expected_error_code=MISSING_ARG,
        expected_error_message="[ERROR   ] argument --upload_id is required"
    )

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_missing_tarchive_path_arg():
    db = get_integration_database_session()

    # Set some tarchive fields
    reset_mri_upload_before_running(db)

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--upload_id', 126,
    ], capture_output=True)

    # Check error code, error message returned and STDERR - will also print out STDERR and STDOUT
    check_error_code_and_process_errors(
        process,
        expected_error_code=MISSING_ARG,
        expected_error_message="[ERROR   ] argument --tarchive_path is required"
    )

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None

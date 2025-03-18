import subprocess

from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from lib.exitcode import GETOPT_FAILURE, INVALID_PATH, MISSING_ARG, SELECT_FAILURE
from tests.util.database import get_integration_database_session


VALID_UPLOAD_ID = 127
VALID_TARCHIVE_PATH = "/data/loris/tarchive/DCM_2016-08-19_OTT203_300203_V3_t1w.tar"
INVALID_TARCHIVE_PATH = "/data/tmp/invalid_path"
INVALID_UPLOAD_ID = 16666


def test_missing_upload_id_arg():
    db = get_integration_database_session()

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--tarchive_path', VALID_TARCHIVE_PATH,
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Isolate STDOUT message and check that it contains the expected error message
    error_msg_is_valid = True \
        if "[ERROR   ] argument --upload_id is required" in process.stdout.decode() \
        else False
    assert error_msg_is_valid is True

    # Check that the return code and standard error are correct
    assert process.returncode == MISSING_ARG
    assert process.stderr == b''

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_missing_tarchive_path_arg():
    db = get_integration_database_session()

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--upload_id', VALID_UPLOAD_ID,
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Isolate STDOUT message and check that it contains the expected error message
    error_msg_is_valid = True \
        if "[ERROR   ] argument --tarchive_path is required" in process.stdout.decode() \
        else False
    assert error_msg_is_valid is True

    # Check that the return code and standard error are correct
    assert process.returncode == MISSING_ARG
    assert process.stderr == b''

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_invalid_arg():
    db = get_integration_database_session()

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--invalid_arg',
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Isolate STDOUT message and check that it contains the expected error message
    error_msg_is_valid = True \
        if "option --invalid_arg not recognized" in process.stdout.decode() \
        else False
    assert error_msg_is_valid is True

    # Check that the return code and standard error are correct
    assert process.returncode == GETOPT_FAILURE
    assert process.stderr == b''

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_invalid_tarchive_path_arg():
    db = get_integration_database_session()

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--tarchive_path', INVALID_TARCHIVE_PATH,
        '--upload_id', VALID_UPLOAD_ID,
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Isolate STDOUT message and check that it contains the expected error message
    error_msg = f"[ERROR   ] {INVALID_TARCHIVE_PATH} does not exist. Please provide a valid path for --tarchive_path"
    error_msg_is_valid = True if error_msg in process.stdout.decode() else False
    assert error_msg_is_valid is True

    # Check that the return code and standard error are correct
    assert process.returncode == INVALID_PATH
    assert process.stderr == b''

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_non_existent_upload_id():
    db = get_integration_database_session()

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--tarchive_path', VALID_TARCHIVE_PATH,
        '--upload_id', INVALID_UPLOAD_ID,
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Isolate STDOUT message and check that it contains the expected error message
    error_msg = f"[ERROR   ] Did not find an entry in mri_upload associated with 'UploadID' {INVALID_UPLOAD_ID}"
    error_msg_is_valid = True if error_msg in process.stderr.decode() else False
    assert error_msg_is_valid is True

    # Check that the return code and standard error are correct
    assert process.returncode == SELECT_FAILURE
    assert process.stderr == b''

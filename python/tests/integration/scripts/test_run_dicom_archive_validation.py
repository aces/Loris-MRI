import subprocess

from sqlalchemy.orm import Session as Database

from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from lib.db.queries.dicom_archive import try_get_dicom_archive_with_id
from lib.exitcode import GETOPT_FAILURE, INVALID_PATH, MISSING_ARG, SELECT_FAILURE
from tests.util.database import get_integration_database_session


def reset_mri_upload_before_running(db: Database):

    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    mri_upload.is_candidate_info_validated = False
    mri_upload.is_dicom_archive_validated = False
    mri_upload.session_id = None
    mri_upload.number_of_minc_created = None
    mri_upload.number_of_minc_inserted = None
    db.commit()


def reset_tarchive_path_before_running(db: Database):

    tarchive = try_get_dicom_archive_with_id(db, 74)
    tarchive.archive_location = "DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar"
    db.commit()


def test_missing_upload_id_arg():
    db = get_integration_database_session()

    # Reset some mri_upload fields
    reset_mri_upload_before_running(db)

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--tarchive_path', '/data/loris/tarchive/DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar',
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
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_missing_tarchive_path_arg():
    db = get_integration_database_session()

    # Reset some mri_upload fields
    reset_mri_upload_before_running(db)

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--upload_id', '126',
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
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_invalid_arg():
    db = get_integration_database_session()

    # Reset some mri_upload fields
    reset_mri_upload_before_running(db)

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--invalid_arg', '126',
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
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_invalid_tarchive_path_arg():
    db = get_integration_database_session()

    # Reset some mri_upload and tarchive fields
    reset_mri_upload_before_running(db)
    reset_tarchive_path_before_running(db)

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--tarchive_path', '/data/loris/DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar',
        '--upload_id', '126',
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Isolate STDOUT message and check that it contains the expected error message
    error_msg = "[ERROR   ] /data/loris/DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar does not exist." \
                " Please provide a valid path for --tarchive_path"
    error_msg_is_valid = True if error_msg in process.stdout.decode() else False
    assert error_msg_is_valid is True

    # Check that the return code and standard error are correct
    assert process.returncode == INVALID_PATH
    assert process.stderr == b''

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_non_existent_upload_id():
    db = get_integration_database_session()

    # Reset some mri_upload and tarchive fields
    reset_mri_upload_before_running(db)
    reset_tarchive_path_before_running(db)

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_validation.py',
        '--profile', 'database_config.py',
        '--tarchive_path', '/data/loris/tarchive/DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar',
        '--upload_id', '16666',
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Isolate STDOUT message and check that it contains the expected error message
    error_msg = "[ERROR   ] Did not find an entry in mri_upload associated with 'UploadID' 16666"
    error_msg_is_valid = True if error_msg in process.stderr.decode() else False
    assert error_msg_is_valid is True

    # Check that the return code and standard error are correct
    assert process.returncode == SELECT_FAILURE
    assert process.stderr == b''

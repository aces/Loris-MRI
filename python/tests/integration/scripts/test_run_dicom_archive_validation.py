from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from lib.exitcode import GETOPT_FAILURE, INVALID_PATH, MISSING_ARG, SELECT_FAILURE, SUCCESS
from tests.util.assert_process import assert_process
from tests.util.database import get_integration_database_session

INVALID_TARCHIVE_PATH = "/data/tmp/invalid_path"
INVALID_UPLOAD_ID = '16666'
VALID_TARCHIVE_PATH = "/data/loris/tarchive/DCM_2016-08-19_OTT203_300203_V3_t1w.tar"
VALID_UPLOAD_ID = '127'


def test_missing_upload_id_arg():
    db = get_integration_database_session()

    # Run the script to test
    assert_process(
        command=[
            'run_dicom_archive_validation.py',
            '--profile', 'database_config.py',
            '--tarchive_path', VALID_TARCHIVE_PATH,
        ],
        return_code=MISSING_ARG,
        stdout="[ERROR   ] argument --upload_id is required",
        stderr=None,
    )

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_missing_tarchive_path_arg():
    db = get_integration_database_session()

    # Run the script to test
    assert_process(
        command=[
            'run_dicom_archive_validation.py',
            '--profile', 'database_config.py',
            '--upload_id', VALID_UPLOAD_ID,
        ],
        return_code=MISSING_ARG,
        stdout="[ERROR   ] argument --tarchive_path is required",
        stderr=None,
    )

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_invalid_arg():
    db = get_integration_database_session()

    assert_process(
        [
            'run_dicom_archive_validation.py',
            '--profile', 'database_config.py',
            '--invalid_arg',
        ],
        return_code=GETOPT_FAILURE,
        stdout="option --invalid_arg not recognized",
        stderr=None,
    )

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_invalid_tarchive_path_arg():
    db = get_integration_database_session()

    # Run the script to test
    assert_process(
        [
            'run_dicom_archive_validation.py',
            '--profile', 'database_config.py',
            '--tarchive_path', INVALID_TARCHIVE_PATH,
            '--upload_id', VALID_UPLOAD_ID,
        ],
        return_code=INVALID_PATH,
        stdout=f"[ERROR   ] {INVALID_TARCHIVE_PATH} does not exist."
                   f" Please provide a valid path for --tarchive_path",
        stderr=None,
    )

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_non_existent_upload_id():

    # Run the script to test
    assert_process(
        [
            'run_dicom_archive_validation.py',
            '--profile', 'database_config.py',
            '--tarchive_path', VALID_TARCHIVE_PATH,
            '--upload_id', INVALID_UPLOAD_ID,
        ],
        return_code=SELECT_FAILURE,
        stdout=None,
        stderr=f"ERROR: Did not find an entry in mri_upload associated with 'UploadID' {INVALID_UPLOAD_ID}",
    )


def test_mixed_up_upload_id_tarchive_path():

    # Run the script to test
    assert_process(
        [
            'run_dicom_archive_validation.py',
            '--profile', 'database_config.py',
            '--tarchive_path', VALID_TARCHIVE_PATH,
            '--upload_id', '126',
        ],
        return_code=SELECT_FAILURE,
        stdout=None,
        stderr=f"ERROR: UploadID 126 and ArchiveLocation {VALID_TARCHIVE_PATH} do not refer to the same upload"
    )


def test_successful_validation():
    db = get_integration_database_session()

    # Run the script to test
    assert_process(
        [
            'run_dicom_archive_validation.py',
            '--profile', 'database_config.py',
            '--tarchive_path', VALID_TARCHIVE_PATH,
            '--upload_id', VALID_UPLOAD_ID,
        ],
        return_code=SUCCESS,
        stdout=None,
        stderr=None,
    )

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is True
    assert mri_upload.is_dicom_archive_validated is True
    assert mri_upload.session is None

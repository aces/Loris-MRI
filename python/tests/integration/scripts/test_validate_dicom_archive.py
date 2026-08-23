from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from lib.exitcode import SELECT_FAILURE, SUCCESS
from tests.util.database import get_integration_database_session
from tests.util.run_integration_script import run_integration_script

INVALID_TARCHIVE_PATH = "/data/tmp/invalid_path"
INVALID_UPLOAD_ID = '16666'
VALID_TARCHIVE_PATH = "/data/loris/tarchive/DCM_2016-08-19_OTT203_300203_V3_t1w.tar"
VALID_UPLOAD_ID = '127'


def test_missing_upload_id_arg():
    db = get_integration_database_session()

    # Run the script to test
    process = run_integration_script([
        'validate-dicom-archive',
        '--dicom-archive-path', VALID_TARCHIVE_PATH,
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == 2
    assert process.stdout == ""
    assert "the following arguments are required: -u/--upload-id" in process.stderr

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_missing_tarchive_path_arg():
    db = get_integration_database_session()

    # Run the script to test
    process = run_integration_script([
        'validate-dicom-archive',
        '--upload-id', VALID_UPLOAD_ID,
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == 2
    assert process.stdout == ""
    assert "the following arguments are required: -t/--dicom-archive-path" in process.stderr

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_invalid_arg():
    db = get_integration_database_session()

    process = run_integration_script([
        'validate-dicom-archive',
        '--dicom-archive-path', VALID_TARCHIVE_PATH,
        '--upload-id', VALID_UPLOAD_ID,
        '--invalid-arg',
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == 2
    assert process.stdout == ""
    assert "unrecognized arguments: --invalid-arg" in process.stderr

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_invalid_tarchive_path_arg():
    db = get_integration_database_session()

    # Run the script to test
    process = run_integration_script([
        'validate-dicom-archive',
        '--dicom-archive-path', INVALID_TARCHIVE_PATH,
        '--upload-id', VALID_UPLOAD_ID,
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == 2
    assert process.stdout == ""
    assert f"argument -t/--dicom-archive-path: {INVALID_TARCHIVE_PATH} does not exist" in process.stderr

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is False
    assert mri_upload.is_dicom_archive_validated is False
    assert mri_upload.session is None


def test_non_existent_upload_id():

    # Run the script to test
    process = run_integration_script([
        'validate-dicom-archive',
        '--dicom-archive-path', VALID_TARCHIVE_PATH,
        '--upload-id', INVALID_UPLOAD_ID,
    ])

    # Check return code, STDOUT and STDERR
    expected_stderr = f"ERROR: Did not find an entry in mri_upload associated with 'UploadID' {INVALID_UPLOAD_ID}"
    assert process.returncode == SELECT_FAILURE
    assert process.stdout == ""
    assert expected_stderr in process.stderr


def test_mixed_up_upload_id_tarchive_path():

    # Run the script to test
    process = run_integration_script([
        'validate-dicom-archive',
        '--dicom-archive-path', VALID_TARCHIVE_PATH,
        '--upload-id', '126',
    ])

    # Check return code, STDOUT and STDERR
    expected_stderr = f"ERROR: UploadID 126 and ArchiveLocation {VALID_TARCHIVE_PATH} do not refer to the same upload"
    assert process.returncode == SELECT_FAILURE
    assert process.stdout == ""
    assert expected_stderr in process.stderr


def test_successful_validation():
    db = get_integration_database_session()

    # Run the script to test
    process = run_integration_script([
        'validate-dicom-archive',
        '--dicom-archive-path', VALID_TARCHIVE_PATH,
        '--upload-id', VALID_UPLOAD_ID,
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stdout == ""
    assert process.stderr == ""

    # Check that the expected data has been inserted in the database
    mri_upload = get_mri_upload_with_patient_name(db, 'OTT203_300203_V3')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is True
    assert mri_upload.is_dicom_archive_validated is True
    assert mri_upload.session is None

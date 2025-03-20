from lib.db.queries.config import set_config_with_setting_name
from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from lib.exitcode import GETOPT_FAILURE, INVALID_PATH, SELECT_FAILURE, SUCCESS
from tests.util.database import get_integration_database_session
from tests.util.file_system import check_file_tree
from tests.util.run_integration_script import run_integration_script


def test_invalid_arg():
    db = get_integration_database_session()

    process = run_integration_script(
        command=[
            'run_dicom_archive_loader.py',
            '--profile', 'database_config.py',
            '--invalid_arg',
        ]
    )

    # Check return code, STDOUT and STDERR
    assert process.returncode == GETOPT_FAILURE
    assert "option --invalid_arg not recognized" in process.stdout
    assert process.stderr == ""


def test_non_existent_upload_id():

    invalid_upload_id = '16666'

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_dicom_archive_loader.py',
            '--profile', 'database_config.py',
            '--upload_id', invalid_upload_id,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stderr = f"ERROR: Did not find an entry in mri_upload associated with 'UploadID' {invalid_upload_id}"
    assert process.returncode == SELECT_FAILURE
    assert process.stdout == ""
    assert expected_stderr in process.stderr


def test_invalid_tarchive_path_arg():

    invalid_tarchive_path = "/data/tmp/invalid_path"

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_dicom_archive_loader.py',
            '--profile', 'database_config.py',
            '--tarchive_path', invalid_tarchive_path,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stdout = f"[ERROR   ] {invalid_tarchive_path} does not exist." \
                      f" Please provide a valid path for --tarchive_path"
    assert process.returncode == INVALID_PATH
    assert expected_stdout in process.stdout
    assert process.stderr == ""


def test_successful_run_on_valid_tarchive_path():
    db = get_integration_database_session()

    # Set the configuration to use the DICOM to BIDS pipeline
    set_config_with_setting_name(db, 'converter', 'dcm2niix')
    db.commit()

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_dicom_archive_loader.py',
            '--profile', 'database_config.py',
            '--tarchive_path', '/data/loris/tarchive/DCM_2015-07-07_MTL001_300001_V2_localizer_t1w.tar',
        ]
    )

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stdout == ""
    assert process.stderr == ""

    # Check that the expected files have been created
    assert check_file_tree('/data/loris/assembly_bids', {
        'sub-300001': {
            'ses-V2': {
                'anat': {
                    'sub-300001_ses-V2_run-1_T1w.json': None,
                    'sub-300001_ses-V2_run-1_T1w.nii.gz': None,
                }
            }
        }
    })

    # Check that the expected data has been inserted in the database
    archive_new_path = '/data/loris/tarchive/2015/DCM_2015-07-07_MTL001_300001_V2_localizer_t1w.tar'
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.inserting is False
    assert mri_upload.insertion_complete is True
    assert mri_upload.is_candidate_info_validated is True
    assert mri_upload.is_dicom_archive_validated is True
    assert mri_upload.number_of_minc_inserted == 1
    assert mri_upload.number_of_minc_created == 1
    assert mri_upload.session is not None
    assert mri_upload.dicom_archive.session_id is not None
    assert mri_upload.dicom_archive.archive_location == archive_new_path
    assert len(mri_upload.session.files) == 1

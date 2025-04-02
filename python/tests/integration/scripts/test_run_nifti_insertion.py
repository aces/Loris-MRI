from lib.db.queries.config import set_config_with_setting_name
from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from lib.exitcode import GETOPT_FAILURE, INVALID_PATH, MISSING_ARG, SELECT_FAILURE, SUCCESS
from tests.util.database import get_integration_database_session
from tests.util.file_system import check_file_tree
from tests.util.run_integration_script import run_integration_script


def test_invalid_arg():

    process = run_integration_script(
        command=[
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--invalid_arg',
        ]
    )

    # Check return code, STDOUT and STDERR
    assert process.returncode == GETOPT_FAILURE
    assert "option --invalid_arg not recognized" in process.stdout
    assert process.stderr == ""


def test_missing_nifti_path_argument():

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stdout = f"[ERROR   ] argument --nifti_path is required"
    assert process.returncode == MISSING_ARG
    assert expected_stdout in process.stdout
    assert process.stderr == ""


def test_invalid_nifti_path():

    nifti_path = '/data/tmp/non-existent-file.nii.gz'

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stdout = f"[ERROR   ] {nifti_path} does not exits. Please provide a valid path for --nifti_path"
    assert process.returncode == INVALID_PATH
    assert expected_stdout in process.stdout
    assert process.stderr == ""


def test_missing_upload_id_or_tarchive_path():

    nifti_path = '/data/loris/incoming/niftis/MTL001_300001_V2_t1_valid.nii.gz'

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stdout = f"[ERROR   ] You should either specify an upload_id or a tarchive_path or use the -force option" \
                      f" (if no upload_id or tarchive_path is available for the NIfTI file to be uploaded)." \
                      f" Make sure that you set only one of those options. Upload will exit now."
    assert process.returncode == MISSING_ARG
    assert expected_stdout in process.stdout
    assert process.stderr == ""


def test_missing_json_path():

    nifti_path = '/data/loris/incoming/niftis/MTL001_300001_V2_t1_valid.nii.gz'
    upload_id = '126'

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
            '--upload_id', upload_id,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stdout = f"[ERROR   ] a json_path or a loris_scan_type need to be provided" \
                      f" in order to determine the image file protocol."
    assert process.returncode == MISSING_ARG
    assert expected_stdout in process.stdout
    assert process.stderr == ""


def test_incorrect_json_path():

    nifti_path = '/data/loris/incoming/niftis/MTL001_300001_V2_t1_valid.nii.gz'
    json_path = '/data/tmp/non-existent-file.json'
    upload_id = '126'

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
            '--upload_id', upload_id,
            '--json_path', json_path,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stdout = f"[ERROR   ] {json_path} does not exist. Please provide a valid path for --json_path"
    assert process.returncode == INVALID_PATH
    assert expected_stdout in process.stdout
    assert process.stderr == ""


def test_invalid_upload_id():

    nifti_path = '/data/loris/incoming/niftis/MTL001_300001_V2_t1_valid.nii.gz'
    json_path = '/data/loris/incoming/niftis/MTL001_300001_V2_t1_valid.json'
    upload_id = '166666'

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
            '--upload_id', upload_id,
            '--json_path', json_path,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stderr = f"[ERROR   ] Did not find an entry in mri_upload associated with 'UploadID' {upload_id}"
    assert process.returncode == SELECT_FAILURE
    assert expected_stderr in process.stderr
    assert process.stdout == ""

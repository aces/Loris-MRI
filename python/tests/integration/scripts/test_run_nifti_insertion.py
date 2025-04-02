from lib.exitcode import GETOPT_FAILURE, INVALID_PATH, MISSING_ARG, SELECT_FAILURE, SUCCESS
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
    assert process.returncode == MISSING_ARG
    assert "[ERROR   ] argument --nifti_path is required" in process.stdout
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
    expected_stdout = f"[ERROR   ] {nifti_path} does not exist. Please provide a valid path for --nifti_path"
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
    expected_stdout = "[ERROR   ] You should either specify an upload_id or a tarchive_path or use the -force option" \
                      " (if no upload_id or tarchive_path is available for the NIfTI file to be uploaded)." \
                      " Make sure that you set only one of those options. Upload will exit now."
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
    expected_stdout = "[ERROR   ] a json_path or a loris_scan_type need to be provided" \
                      " in order to determine the image file protocol."
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
    expected_stderr = f"ERROR: Did not find an entry in mri_upload associated with 'UploadID' {upload_id}"
    assert process.returncode == SELECT_FAILURE
    assert expected_stderr in process.stderr
    assert process.stdout == ""


def test_invalid_tarchive_path():

    nifti_path = '/data/loris/incoming/niftis/MTL001_300001_V2_t1_valid.nii.gz'
    json_path = '/data/loris/incoming/niftis/MTL001_300001_V2_t1_valid.json'
    tarchive_path = '/data/tmp/non-existent-tarchive.tgz'

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
            '--tarchive_path', tarchive_path,
            '--json_path', json_path,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stdout = f"[ERROR   ] {tarchive_path} does not exist. Please provide a valid path for --tarchive_path"
    assert process.returncode == INVALID_PATH
    assert expected_stdout in process.stdout
    assert process.stderr == ""


def test_tarchive_path_and_upload_id_provided():

    nifti_path = '/data/loris/incoming/niftis/MTL001_300001_V2_t1_valid.nii.gz'
    json_path = '/data/loris/incoming/niftis/MTL001_300001_V2_t1_valid.json'
    tarchive_path = '/data/tmp/non-existent-tarchive.tgz'
    upload_id = '126'

    # Run the script to test
    process = run_integration_script(
        command=[
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
            '--tarchive_path', tarchive_path,
            '--upload_id', upload_id,
            '--json_path', json_path,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stdout = "ERROR   ] You should either specify an upload_id or a tarchive_path or use the -force option" \
                      " (if no upload_id or tarchive_path is available for the NIfTI file to be uploaded)." \
                      " Make sure that you set only one of those options. Upload will exit now."
    assert process.returncode == GETOPT_FAILURE
    assert expected_stdout in process.stdout
    assert process.stderr == ""

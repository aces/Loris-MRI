from lib.exitcode import FILENAME_MISMATCH, FILE_NOT_UNIQUE, GETOPT_FAILURE, INVALID_PATH, MISSING_ARG, SELECT_FAILURE
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

    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t1_valid.nii.gz'

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

    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t1_valid.nii.gz'
    upload_id = '128'

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

    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t1_valid.nii.gz'
    json_path = '/data/tmp/non-existent-file.json'
    upload_id = '128'

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

    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t1_valid.nii.gz'
    json_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t1_valid.json'
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

    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t1_valid.nii.gz'
    json_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t1_valid.json'
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

    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t1_valid.nii.gz'
    json_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t1_valid.json'
    tarchive_path = '/data/loris/tarchive/DCM_2016-08-19_ROM184_400184_V3_for_nifti_insertion.tar'
    upload_id = '128'

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
    expected_stdout = "[ERROR   ] You should either specify an upload_id or a tarchive_path or use the -force option" \
                      " (if no upload_id or tarchive_path is available for the NIfTI file to be uploaded)." \
                      " Make sure that you set only one of those options. Upload will exit now."
    assert process.returncode == MISSING_ARG
    assert expected_stdout in process.stdout
    assert process.stderr == ""


def test_nifti_and_tarchive_patient_name_differ():

    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t2_invalid_pname.nii.gz'
    json_path = '/data/loris/incoming/niftis/ROM184_400184_V3_t2_invalid_pname.json'
    upload_id = '128'

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
    expected_stderr = "ERROR: PatientName in DICOM and NIfTI files differ."
    assert process.returncode == FILENAME_MISMATCH
    assert expected_stderr in process.stderr
    assert process.stdout == ""


def test_nifti_already_uploaded():

    series_uid = '1.3.12.2.1107.5.2.32.35412.2012101116562350450995317.0.0.0'
    nifti_path = '/data/loris/assembly_bids/sub-400184/ses-V3/func/sub-400184_ses-V3_task-rest_run-1_bold.nii.gz'
    json_path = '/data/loris/assembly_bids/sub-400184/ses-V3/func/sub-400184_ses-V3_task-rest_run-1_bold.json'
    upload_id = '128'

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
    expected_stderr = f"ERROR: There is already a file registered in the files table with SeriesUID {series_uid}," \
                      f" EchoTime 0.027, EchoNumber None and PhaseEncodingDirection j-. The already registered" \
                      f" file is {nifti_path.replace('/data/loris/', '')}"
    assert process.returncode == FILE_NOT_UNIQUE
    assert expected_stderr in process.stderr
    assert process.stdout == ""

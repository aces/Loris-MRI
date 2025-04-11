import os.path
from os.path import basename

from lib.db.queries.file import (
    try_get_file_with_unique_combination,
    try_get_parameter_value_with_file_id_parameter_name,
)
from lib.db.queries.mri_protocol_violated_scans import try_get_protocol_violated_scans_with_unique_series_combination
from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from lib.db.queries.mri_violations_log import try_get_violations_log_with_unique_series_combination
from lib.exitcode import (
    FILE_NOT_UNIQUE,
    FILENAME_MISMATCH,
    GETOPT_FAILURE,
    INVALID_PATH,
    MISSING_ARG,
    SELECT_FAILURE,
    SUCCESS,
    UNKNOWN_PROTOCOL,
)
from tests.util.database import get_integration_database_session
from tests.util.file_system import check_file_tree
from tests.util.run_integration_script import run_integration_script


def test_invalid_arg():

    process = run_integration_script(
        [
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
        [
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
        [
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
        [
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
        [
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
        [
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
        [
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
        [
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
        [
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
        [
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
        [
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


def test_nifti_mri_protocol_violated_scans_insertion():
    db = get_integration_database_session()

    series_uid = '1.3.12.2.1107.5.2.32.35412.2012101116361477745078942.0.0.0'
    phase_encoding_direction = 'i'
    echo_time = '0.005'
    echo_number = None
    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_unknown_scan_type.nii.gz'
    json_path = '/data/loris/incoming/niftis/ROM184_400184_V3_unknown_scan_type.json'
    upload_id = '128'

    # Run the script to test
    process = run_integration_script(
        [
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
            '--upload_id', upload_id,
            '--json_path', json_path,
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stderr = f"ERROR: {nifti_path}'s acquisition protocol is 'unknown'."
    assert process.returncode == UNKNOWN_PROTOCOL
    assert expected_stderr in process.stderr
    assert process.stdout == ""

    # Check that the expected data has been inserted in the database in the proper table
    mri_upload = get_mri_upload_with_patient_name(db, 'ROM184_400184_V3')
    violated_scans = try_get_protocol_violated_scans_with_unique_series_combination(
        db,
        series_uid,
        echo_time,
        echo_number,
        phase_encoding_direction
    )
    # Check that the NIfTI file was not inserted in files table (still only one file in the files table)
    assert mri_upload.session and len(mri_upload.session.files) == 1
    # Check that the NIfTI file got inserted in the mri_protocol_violated_scans table
    assert violated_scans is not None

    # Check that the NIfTI file can be found on the disk
    assert violated_scans.minc_location is not None \
           and os.path.exists(os.path.join('/data/loris/', str(violated_scans.minc_location)))


def test_nifti_mri_violations_log_exclude_insertion():
    db = get_integration_database_session()

    series_uid = '1.3.12.2.1107.5.2.32.35412.2012101117085370136129517.0.0.0'
    phase_encoding_direction = 'j-'
    echo_time = '0.103'
    echo_number = None
    expected_violation = [{
        'Severity': 'exclude',
        'Header': 'repetition_time',
        'Value': 11.2,
        'ValidRange': '11.1-11.1',
        'ValidRegex': None,
        'MriProtocolChecksGroupID': 1
    }]
    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_violation_log_exclude.nii.gz'
    json_path = '/data/loris/incoming/niftis/ROM184_400184_V3_violation_log_exclude.json'
    bval_path = '/data/loris/incoming/niftis/ROM184_400184_V3_violation_log_exclude.bval'
    bvec_path = '/data/loris/incoming/niftis/ROM184_400184_V3_violation_log_exclude.bvec'
    upload_id = '128'

    # Run the script to test
    process = run_integration_script(
        [
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
            '--upload_id', upload_id,
            '--json_path', json_path,
            '--bval_path', bval_path,
            '--bvec_path', bvec_path
        ]
    )

    # Check return code, STDOUT and STDERR
    expected_stderr = f"ERROR: {nifti_path} violates exclusionary checks listed in mri_protocol_checks." \
                      f" List of violations are: {expected_violation}"
    assert process.returncode == UNKNOWN_PROTOCOL
    assert expected_stderr in process.stderr
    assert process.stdout == ""

    # Check that the expected data has been inserted in the database in the proper table
    mri_upload = get_mri_upload_with_patient_name(db, 'ROM184_400184_V3')
    violations_log = try_get_violations_log_with_unique_series_combination(
        db,
        series_uid,
        echo_time,
        echo_number,
        phase_encoding_direction
    )
    # Check that the NIfTI file was not inserted in files table (still only one file in the files table)
    assert mri_upload.session and len(mri_upload.session.files) == 1
    # Check that the NIfTI file got inserted in the mri_protocol_violated_scans table and the attached file
    # can be found on the disk
    assert violations_log is not None and len(violations_log) == 1

    # Check that the NIfTI file can be found in the filesystem
    violation_entry = violations_log[0]
    assert violation_entry.minc_file is not None \
           and os.path.exists(os.path.join('/data/loris/', str(violation_entry.minc_file)))
    # Check that the rest of the expected files have been created
    path_parts = os.path.split(str(violation_entry.minc_file))
    file_name = path_parts[-1]
    dir_path = os.path.join('/data/loris/', path_parts[0])
    assert check_file_tree(dir_path, {
        file_name: None,
        file_name.replace('.nii.gz', '.bval'): None,
        file_name.replace('.nii.gz', '.bvec'): None,
        file_name.replace('.nii.gz', '.json'): None,
    })

    # Rerun the script to test that it did not duplicate entry in MRI violations log
    process = run_integration_script(
        [
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
            '--upload_id', upload_id,
            '--json_path', json_path,
            '--bval_path', bval_path,
            '--bvec_path', bvec_path
        ]
    )

    assert process.returncode == UNKNOWN_PROTOCOL
    assert expected_stderr in process.stderr
    assert process.stdout == ""

    # assert violations_log is not None and len(violations_log) == 1


def test_dwi_insertion_with_mri_violations_log_warning():
    db = get_integration_database_session()

    series_uid = '1.3.12.2.1107.5.2.32.35412.2012101116492064679881426.0.0.0'
    phase_encoding_direction = 'j-'
    echo_time = '0.102'
    echo_number = None
    nifti_path = '/data/loris/incoming/niftis/ROM184_400184_V3_violation_log_warning.nii.gz'
    json_path = '/data/loris/incoming/niftis/ROM184_400184_V3_violation_log_warning.json'
    bval_path = '/data/loris/incoming/niftis/ROM184_400184_V3_violation_log_warning.bval'
    bvec_path = '/data/loris/incoming/niftis/ROM184_400184_V3_violation_log_warning.bvec'
    upload_id = '128'

    # Run the script to test
    process = run_integration_script(
        [
            'run_nifti_insertion.py',
            '--profile', 'database_config.py',
            '--nifti_path', nifti_path,
            '--upload_id', upload_id,
            '--json_path', json_path,
            '--bval_path', bval_path,
            '--bvec_path', bvec_path,
            '--create_pic'
        ]
    )

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stderr == ""
    assert process.stdout == ""

    # Check that the expected data has been inserted in the database in the proper table
    file = try_get_file_with_unique_combination(
        db,
        series_uid,
        echo_time,
        echo_number,
        phase_encoding_direction
    )
    violations_log = try_get_violations_log_with_unique_series_combination(
        db,
        series_uid,
        echo_time,
        echo_number,
        phase_encoding_direction
    )

    # Check that the NIfTI file was inserted in `files` and `mri_violations_log` tables
    assert file is not None
    assert violations_log is not None and len(violations_log) == 1
    violation_entry = violations_log[0]
    assert violation_entry.minc_file is not None
    assert violation_entry.severity == 'warning'

    # Check that all files related to that image have been properly linked in the database
    file_base_rel_path = 'assembly_bids/sub-400184/ses-V3/dwi/sub-400184_ses-V3_acq-25dir_run-1_dwi'
    assert str(violation_entry.minc_file) \
           == str(file.file_name) \
           == f'{file_base_rel_path}.nii.gz'
    file_json_data = try_get_parameter_value_with_file_id_parameter_name(db, file.id, 'bids_json_file')
    file_bval_data = try_get_parameter_value_with_file_id_parameter_name(db, file.id, 'check_bval_filename')
    file_bvec_data = try_get_parameter_value_with_file_id_parameter_name(db, file.id, 'check_bvec_filename')
    file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, file.id, 'check_pic_filename')
    assert file_json_data is not None and file_json_data.value == f'{file_base_rel_path}.json'
    assert file_bval_data is not None and file_bval_data.value == f'{file_base_rel_path}.bval'
    assert file_bvec_data is not None and file_bvec_data.value == f'{file_base_rel_path}.bvec'
    assert file_pic_data is not None

    assert check_file_tree('/data/loris/', {
        'assembly_bids': {
            'sub-400184': {
                'ses-V3': {
                    'dwi': {
                        basename(str(file.file_name)): None,
                        basename(str(file_bval_data.value)): None,
                        basename(str(file_bvec_data.value)): None,
                        basename(str(file_json_data.value)): None,
                    }
                }
            }
        },
        'pic': {
            '400184': {
                basename(str(file_pic_data.value)): None
            }
        }
    })

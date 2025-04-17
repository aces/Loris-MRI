import time
from datetime import datetime

from lib.db.models.file import DbFile
from lib.db.queries.file import try_get_parameter_value_with_file_id_parameter_name
from lib.db.queries.parameter_file import delete_file_parameter
from lib.exitcode import INVALID_ARG, MISSING_ARG, SUCCESS
from tests.util.database import get_integration_database_session
from tests.util.run_integration_script import run_integration_script


def test_missing_profile_arg():

    process = run_integration_script([
        'mass_nifti_pic.py',
    ])

    # Check return code, STDOUT and STDERR
    message = 'ERROR: you must specify a profile file using -p or --profile option'
    assert process.returncode == MISSING_ARG
    assert message in process.stdout
    assert process.stderr == ""


def test_invalid_profile_arg():

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'invalid_profile.py'
    ])

    # Check return code, STDOUT and STDERR
    message = 'ERROR: you must specify a valid profile file.\ninvalid_profile.py does not exist!'
    assert process.returncode == MISSING_ARG
    assert message in process.stdout
    assert process.stderr == ""


def test_missing_smallest_id_arg():

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'database_config.py',
    ])

    # Check return code, STDOUT and STDERR
    message = 'ERROR: you must specify a smallest FileID on which to run' \
              ' the mass_nifti_pic.py script using -s or --smallest_id option'
    assert process.returncode == MISSING_ARG
    assert message in process.stdout
    assert process.stderr == ""


def test_missing_largest_id_arg():

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'database_config.py',
        '--smallest_id', '2',
    ])

    # Check return code, STDOUT and STDERR
    message = 'ERROR: you must specify a largest FileID on which to run the' \
              ' mass_nifti_pic.py script using -l or --largest_id option'
    assert process.returncode == MISSING_ARG
    assert message in process.stdout
    assert process.stderr == ""


def test_smallest_id_bigger_than_largest_id():

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'database_config.py',
        '--smallest_id', '6',
        '--largest_id', '2'
    ])

    # Check return code, STDOUT and STDERR
    message = 'ERROR: the value for --smallest_id option is bigger than value for --largest_id option'
    assert process.returncode == INVALID_ARG
    assert message in process.stdout
    assert process.stderr == ""


def test_on_invalid_file_id():

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'database_config.py',
        '--smallest_id', '999',
        '--largest_id', '999'
    ])

    # Check return code, STDOUT and STDERR
    message = 'WARNING: no file in the database with FileID = 999'
    assert process.returncode == SUCCESS
    assert message in process.stdout
    assert process.stderr == ""


def test_on_file_id_that_already_has_a_pic():

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'database_config.py',
        '--smallest_id', '2',
        '--largest_id', '2'
    ])

    # Check return code, STDOUT and STDERR
    message = 'WARNING: there is already a pic for FileID 2. Use -f or --force to overwrite it'
    assert process.returncode == SUCCESS
    assert message in process.stdout
    assert process.stderr == ""


def test_force_option():

    # database connection
    db = get_integration_database_session()

    # file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, 2, 'check_pic_filename')

    current_time = time.time()

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'database_config.py',
        '--smallest_id', '2',
        '--largest_id', '2',
        '--force'
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stdout == ""
    assert process.stderr == ""

    file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, 2, 'check_pic_filename')
    assert file_pic_data is not None and file_pic_data.insert_time >= current_time


def test_running_on_non_nifti_file():

    # database connection
    db = get_integration_database_session()

    # insert fake text file with file ID 1
    file = DbFile()
    file.id                  = 1
    file.rel_path            = 'test.txt'
    file.file_type           = 'txt'
    file.session_id          = 564
    file.output_type         = 'native'
    file.insert_time         = int(datetime.now().timestamp())
    file.inserted_by_user_id = 'test'
    db.add(file)
    db.commit()

    # run NIfTI pic script on the inserted file
    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'database_config.py',
        '--smallest_id', '1',
        '--largest_id', '1'
    ])

    # Check return code, STDOUT and STDERR
    message = 'WARNING: wrong file type. File test.txt is not a .nii.gz file'
    assert process.returncode == SUCCESS
    assert message in process.stdout
    assert process.stderr == ""


def test_successful_run():

    # database connection
    db = get_integration_database_session()
    file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, 2, 'check_pic_filename')
    if file_pic_data:
        # delete pic entry based on it parameter file ID
        delete_file_parameter(db, file_pic_data.id)
        db.commit()
    file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, 2, 'check_pic_filename')
    assert file_pic_data is None

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'database_config.py',
        '--smallest_id', '2',
        '--largest_id', '2'
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stdout == ""
    assert process.stderr == ""

import os
from datetime import datetime
from pathlib import Path

from lib.db.models.file import DbFile
from lib.db.queries.file import delete_file
from lib.db.queries.file_parameter import delete_file_parameter, try_get_parameter_value_with_file_id_parameter_name
from lib.exitcode import INVALID_ARG, INVALID_PATH, SUCCESS
from tests.util.database import get_integration_database_session
from tests.util.run_integration_script import run_integration_script


def test_invalid_profile_arg():
    """
    Test running the script with an invalid --profile argument.
    """

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--profile', 'invalid_profile.py',
        '--smallest-id', '1',
        '--largest-id', '1',
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == INVALID_PATH
    assert process.stdout == ""
    assert process.stderr == "ERROR: No configuration file 'invalid_profile.py' found in the '/opt/loris/bin/mri/config' directory.\n"  # noqa: E501


def test_smallest_id_bigger_than_largest_id():
    """
    Test running the script with a --smallest-id higher than the --largest-id.
    """

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--smallest-id', '6',
        '--largest-id', '2'
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == INVALID_ARG
    assert process.stdout == ""
    assert process.stderr == "ERROR: The --smallest-id value should be smaller than the --largest-id value\n"


def test_on_invalid_file_id():
    """
    Test running the script on an invalid file ID.
    """

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--smallest-id', '999',
        '--largest-id', '999'
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stdout == ""
    assert process.stderr == "WARNING: No file with ID 999 in the database, skipping.\n"


def test_on_file_id_that_already_has_a_pic():
    """
    Test running the script on a file that already has a pic.
    """

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--smallest-id', '2',
        '--largest-id', '2'
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stdout == ""
    assert process.stderr == "WARNING: There is already a pic for file ID 2. Use -f or --force to overwrite it, skipping.\n"  # noqa: E501


def test_force_option():
    """
    Test running the script on a file that already has the pic with option --force.
    """

    # database connection
    db = get_integration_database_session()
    file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, 2, 'check_pic_filename')
    assert file_pic_data is not None
    # remove file from the file system before recreating it
    # otherwise get Operation Not Permitted (specific to the test environment)
    # TODO: Investigate
    pic_to_remove = os.path.join('/data/loris/pic/', str(file_pic_data.value))
    if os.path.exists(pic_to_remove):
        os.remove(pic_to_remove)

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--smallest-id', '2',
        '--largest-id', '2',
        '--force'
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stdout == "Creating preview picture for NIfTI file ID 2\n"
    assert process.stderr == ""

    file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, 2, 'check_pic_filename')
    assert file_pic_data is not None
    assert file_pic_data.value is not None
    assert os.path.exists(os.path.join('/data/loris/pic/', str(file_pic_data.value)))


def test_running_on_a_text_file():
    """
    Test running the script on a text file (a non-NIfTI file type).
    """

    # database connection
    db = get_integration_database_session()

    # insert fake text file
    file = DbFile(
        path                = Path('test.txt'),
        file_type           = 'txt',
        session_id          = 564,
        output_type         = 'native',
        insert_time         = datetime.now(),
        inserted_by_user_id = 'test'
    )

    db.add(file)
    db.commit()

    # run NIfTI pic script on the inserted file
    process = run_integration_script([
        'mass_nifti_pic.py',
        '--smallest-id', str(file.id),
        '--largest-id', str(file.id)
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stdout == ""
    assert process.stderr == "WARNING: Wrong file type. File 'test.txt' is not a .nii.gz file, skipping.\n"

    # Clean up the file that was inserted before this test
    delete_file(db, file.id)
    db.commit()


def test_successful_run():
    """
    Test successful run of the script.
    """

    # database connection
    db = get_integration_database_session()

    # Remove file ID 2 pic from the database and filesystem
    file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, 2, 'check_pic_filename')
    assert file_pic_data is not None
    # remove file from the file system before recreating it
    # otherwise get Operation Not Permitted (specific to the test environment)
    # TODO: Investigate
    pic_to_remove = os.path.join('/data/loris/pic/', str(file_pic_data.value))
    if os.path.exists(pic_to_remove):
        os.remove(pic_to_remove)
    # delete pic entry based on its parameter file ID
    delete_file_parameter(db, file_pic_data.id)
    db.commit()

    file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, 2, 'check_pic_filename')
    assert file_pic_data is None

    current_time = datetime.now()

    process = run_integration_script([
        'mass_nifti_pic.py',
        '--smallest-id', '2',
        '--largest-id', '2'
    ])

    # Check return code, STDOUT and STDERR
    assert process.returncode == SUCCESS
    assert process.stdout == "Creating preview picture for NIfTI file ID 2\n"
    assert process.stderr == ""

    # check pic in database and file system
    file_pic_data = try_get_parameter_value_with_file_id_parameter_name(db, 2, 'check_pic_filename')
    assert file_pic_data is not None
    assert file_pic_data.insert_time >= current_time
    assert file_pic_data.value is not None
    assert os.path.exists(os.path.join('/data/loris/pic/', str(file_pic_data.value)))

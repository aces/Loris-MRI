import subprocess

from lib.db.queries.config import set_config_with_setting_name
from lib.db.queries.mri_upload import get_mri_upload_with_patient_name
from tests.util.database import get_integration_database_session
from tests.util.file_system import check_file_tree


def test():
    db = get_integration_database_session()

    # Set the configuration to use the DICOM to BIDS pipeline
    set_config_with_setting_name(db, 'converter', 'dcm2niix')
    db.commit()

    # Run the script to test
    process = subprocess.run([
        'run_dicom_archive_loader.py',
        '--profile', 'database_config.py',
        '--tarchive_path', '/data/loris/tarchive/DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar',
    ], capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Check that the return code and standard error are correct
    assert process.returncode == 0
    assert process.stderr == b''

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
    mri_upload = get_mri_upload_with_patient_name(db, 'MTL001_300001_V2')
    assert mri_upload.inserting is False
    assert mri_upload.is_candidate_info_validated is True
    assert mri_upload.is_dicom_archive_validated is True
    assert mri_upload.session is not None
    assert len(mri_upload.session.files) == 1

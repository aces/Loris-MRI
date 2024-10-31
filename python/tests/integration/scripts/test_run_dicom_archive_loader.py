import os
import subprocess


def test():
    process = subprocess.run([
        'run_dicom_archive_loader.py',
        '--profile', 'database_config.py',
        '--tarchive_path', '/data/loris/tarchive/DCM_2015-07-07_ImagingUpload-14-30-FoTt1K.tar',
        # Only one of the DICOM archive path or the upload ID should be specified
        # '--upload_id', '126',
    ], capture_output=True)

    assert process.returncode == 0
    assert process.stderr == b''
    assert os.path.exists('/data/loris/assembly_bids/sub-300001')

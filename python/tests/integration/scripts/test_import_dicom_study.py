import os

from lib.db.queries.dicom_archive import try_get_dicom_archive_with_patient_name
from tests.util.database import get_integration_database_session
from tests.util.run_integration_script import run_integration_script


def test_import_dicom_study():
    db = get_integration_database_session()

    process = run_integration_script([
        'import_dicom_study.py',
        '--source', '/data/loris/incoming/ROM168_400168_V2',
        '--insert', '--session',
    ])

    # Check the return code and standard error output.
    assert process.returncode == 0
    assert process.stderr == ""

    # Check that the expected DICOM archive file has been created.
    assert os.path.isfile('/data/loris/tarchive/2016/DCM_2016-08-19_ROM168_400168_V2.tar')

    # Check that the expected data has been inserted in the database.
    dicom_archive = try_get_dicom_archive_with_patient_name(db, 'ROM168_400168_V2')
    assert dicom_archive is not None
    assert len(dicom_archive.series) == 32
    assert len(dicom_archive.files) == 609
    assert dicom_archive.session is not None
    assert dicom_archive.session.candidate.psc_id == 'ROM168'
    assert dicom_archive.session.visit_label == 'V2'

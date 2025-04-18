from dataclasses import dataclass

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.dicom_archive_file import DbDicomArchiveFile
from lib.db.models.dicom_archive_series import DbDicomArchiveSeries
from lib.db.queries.dicom_archive import delete_dicom_archive_file_series, try_get_dicom_archive_with_study_uid
from tests.util.database import create_test_database


@dataclass
class Setup:
    db: Database
    dicom_archive: DbDicomArchive
    dicom_archive_series: DbDicomArchiveSeries


@pytest.fixture
def setup():
    db = create_test_database()

    dicom_archive_1 = DbDicomArchive(
        study_uid                 = '1.2.256.100000.1.2.3.456789',
        patient_id                = 'DCC001_111111_V1',
        patient_name              = 'DCC001_111111_V1',
        center_name               = 'Test center',
        acquisition_count         = 2,
        dicom_file_count          = 2,
        non_dicom_file_count      = 0,
        creating_user             = 'admin',
        sum_type_version          = 2,
        tar_type_version          = 2,
        source_location           = '/tests/DCC001_111111_V1',
        scanner_manufacturer      = 'Test scanner manufacturer',
        scanner_model             = 'Test scanner model',
        scanner_serial_number     = 'Test scanner serial number',
        scanner_software_version  = 'Test scanner software version',
        upload_attempt            = 0,
        acquisition_metadata      = '',
        pending_transfer          = False,
    )

    dicom_archive_2 = DbDicomArchive(
        study_uid                 = '2.16.999.1.2.3.456789',
        patient_id                = 'DCC002_222222_V2',
        patient_name              = 'DCC002_222222_V2',
        center_name               = 'Test center',
        acquisition_count         = 1,
        dicom_file_count          = 1,
        non_dicom_file_count      = 0,
        creating_user             = 'admin',
        sum_type_version          = 2,
        tar_type_version          = 2,
        source_location           = '/test/DCC002_222222_V2',
        scanner_manufacturer      = 'Test scanner manufacturer',
        scanner_model             = 'Test scanner model',
        scanner_serial_number     = 'Test scanner serial number',
        scanner_software_version  = 'Test scanner software version',
        upload_attempt            = 0,
        acquisition_metadata      = '',
        pending_transfer          = False,
    )

    db.add(dicom_archive_1)
    db.add(dicom_archive_2)
    db.flush()

    dicom_archive_series_1_1 = DbDicomArchiveSeries(
        archive_id         = dicom_archive_1.id,
        series_number      = 1,
        sequence_name      = 'ep_b100',
        echo_time          = 100,
        number_of_files    = 1,
        series_uid         = '1.3.12.2.11.11.11.999.0.0',
        modality           = 'MR',
    )

    dicom_archive_series_1_2 = DbDicomArchiveSeries(
        archive_id         = dicom_archive_1.id,
        series_number      = 2,
        sequence_name      = 'ep_b200',
        echo_time          = 200,
        number_of_files    = 1,
        series_uid         = '1.3.12.2.11.11.11.999.0.0',
        modality           = 'MR',
    )

    dicom_archive_series_2_1 = DbDicomArchiveSeries(
        archive_id         = dicom_archive_2.id,
        series_number      = 1,
        sequence_name      = 'ep_b100',
        echo_time          = 100,
        number_of_files    = 1,
        series_uid         = '1.3.12.2.99.99.99.1111.0.0',
        modality           = 'MR',
    )

    db.add(dicom_archive_series_1_1)
    db.add(dicom_archive_series_1_2)
    db.add(dicom_archive_series_2_1)
    db.flush()

    dicom_archive_file_1_1 = DbDicomArchiveFile(
        archive_id = dicom_archive_1.id,
        series_id  = dicom_archive_series_1_1.id,
        md5_sum    = '01234567890abcdef0123456789abcde',
        file_name  = '1.1.dcm',
    )

    dicom_archive_file_1_2 = DbDicomArchiveFile(
        archive_id = dicom_archive_1.id,
        series_id  = dicom_archive_series_1_2.id,
        md5_sum    = '01234567890abcdef0123456789abcde',
        file_name  = '1.2.dcm',
    )

    dicom_archive_file_2_1 = DbDicomArchiveFile(
        archive_id = dicom_archive_2.id,
        series_id  = dicom_archive_series_2_1.id,
        md5_sum    = '01234567890abcdef0123456789abcde',
        file_name  = '2.1.dcm',
    )

    db.add(dicom_archive_file_1_1)
    db.add(dicom_archive_file_1_2)
    db.add(dicom_archive_file_2_1)
    db.flush()

    return Setup(db, dicom_archive_1, dicom_archive_series_1_1)


def test_try_get_dicom_archive_with_study_uid_some(setup: Setup):
    dicom_archive = try_get_dicom_archive_with_study_uid(
        setup.db,
        '1.2.256.100000.1.2.3.456789',
    )

    assert dicom_archive is setup.dicom_archive


def test_try_get_dicom_archive_with_study_uid_none(setup: Setup):
    dicom_archive = try_get_dicom_archive_with_study_uid(
        setup.db,
        '1.2.256.999999.9.8.7654321',
    )

    assert dicom_archive is None


def test_delete_dicom_archive_file_series(setup: Setup):
    delete_dicom_archive_file_series(setup.db, setup.dicom_archive)

    assert setup.db.execute(select(DbDicomArchiveFile)
        .where(DbDicomArchiveFile.archive_id == setup.dicom_archive.id)).first() is None

    assert setup.db.execute(select(DbDicomArchiveSeries)
        .where(DbDicomArchiveSeries.archive_id == setup.dicom_archive.id)).first() is None

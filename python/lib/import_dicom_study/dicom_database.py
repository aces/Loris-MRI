from datetime import datetime
from functools import cmp_to_key
from pathlib import Path

from sqlalchemy.orm import Session as Database

from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.dicom_archive_file import DbDicomArchiveFile
from lib.db.models.dicom_archive_series import DbDicomArchiveSeries
from lib.db.queries.dicom_archive import delete_dicom_archive_file_series
from lib.import_dicom_study.import_log import DicomStudyImportLog, write_dicom_study_import_log_to_string
from lib.import_dicom_study.summary_type import DicomStudySummary
from lib.import_dicom_study.summary_write import compare_dicom_files, compare_dicom_series, write_dicom_study_summary
from lib.util.iter import count, flatten


def insert_dicom_archive(
    db: Database,
    dicom_summary: DicomStudySummary,
    dicom_import_log: DicomStudyImportLog,
    archive_path: Path,
):
    """
    Insert a DICOM archive in the database.
    """

    dicom_archive = DbDicomArchive()
    populate_dicom_archive(dicom_archive, dicom_summary, dicom_import_log, archive_path)
    dicom_archive.date_first_archived = datetime.now()
    db.add(dicom_archive)
    db.commit()
    insert_files_series(db, dicom_archive, dicom_summary)
    return dicom_archive


def update_dicom_archive(
    db: Database,
    dicom_archive: DbDicomArchive,
    dicom_summary: DicomStudySummary,
    dicom_import_log: DicomStudyImportLog,
    archive_path: Path,
):
    """
    Update a DICOM archive in the database.
    """

    # Delete the associated database DICOM files and series.
    delete_dicom_archive_file_series(db, dicom_archive)

    # Update the database record with the new DICOM information.
    populate_dicom_archive(dicom_archive, dicom_summary, dicom_import_log, archive_path)
    db.commit()

    # Insert the new DICOM files and series.
    insert_files_series(db, dicom_archive, dicom_summary)


def populate_dicom_archive(
    dicom_archive: DbDicomArchive,
    dicom_summary: DicomStudySummary,
    dicom_import_log: DicomStudyImportLog,
    archive_path: Path,
):
    """
    Populate a DICOM archive database object with information from its DICOM summary and DICOM
    study import log.
    """

    dicom_archive.study_uid                = dicom_summary.info.study_uid
    dicom_archive.patient_id               = dicom_summary.info.patient.id
    dicom_archive.patient_name             = dicom_summary.info.patient.name
    dicom_archive.patient_birthdate        = dicom_summary.info.patient.birth_date
    dicom_archive.patient_sex              = dicom_summary.info.patient.sex
    dicom_archive.neuro_db_center_name     = None
    dicom_archive.center_name              = dicom_summary.info.institution or ''
    dicom_archive.last_update              = None
    dicom_archive.date_acquired            = dicom_summary.info.scan_date
    dicom_archive.date_last_archived       = datetime.now()
    dicom_archive.acquisition_count        = len(dicom_summary.dicom_series_files)
    dicom_archive.dicom_file_count         = count(flatten(dicom_summary.dicom_series_files.values()))
    dicom_archive.non_dicom_file_count     = len(dicom_summary.other_files)
    dicom_archive.md5_sum_dicom_only       = dicom_import_log.tarball_md5_sum
    dicom_archive.md5_sum_archive          = dicom_import_log.archive_md5_sum
    dicom_archive.creating_user            = dicom_import_log.creator_name
    dicom_archive.sum_type_version         = dicom_import_log.summary_version
    dicom_archive.tar_type_version         = dicom_import_log.archive_version
    dicom_archive.source_path              = dicom_import_log.source_path
    dicom_archive.archive_path             = archive_path
    dicom_archive.scanner_manufacturer     = dicom_summary.info.scanner.manufacturer or ''
    dicom_archive.scanner_model            = dicom_summary.info.scanner.model or ''
    dicom_archive.scanner_serial_number    = dicom_summary.info.scanner.serial_number or ''
    dicom_archive.scanner_software_version = dicom_summary.info.scanner.software_version or ''
    dicom_archive.session_id               = None
    dicom_archive.upload_attempt           = 0
    dicom_archive.create_info              = write_dicom_study_import_log_to_string(dicom_import_log)
    dicom_archive.acquisition_metadata     = write_dicom_study_summary(dicom_summary)
    dicom_archive.date_sent                = None
    dicom_archive.pending_transfer         = False


def insert_files_series(db: Database, dicom_archive: DbDicomArchive, dicom_summary: DicomStudySummary):
    """
    Insert the DICOM files and series related to a DICOM archive in the database.
    """

    # Sort the DICOM series and files to insert them in the correct order.
    dicom_series_list = list(dicom_summary.dicom_series_files.keys())
    dicom_series_list.sort(key=cmp_to_key(compare_dicom_series))

    for dicom_series in dicom_series_list:
        dicom_files = dicom_summary.dicom_series_files[dicom_series]
        dicom_files.sort(key=cmp_to_key(compare_dicom_files))

        dicom_series = DbDicomArchiveSeries(
            archive_id         = dicom_archive.id,
            series_number      = dicom_series.series_number,
            series_description = dicom_series.series_description,
            sequence_name      = dicom_series.sequence_name,
            echo_time          = dicom_series.echo_time,
            repetition_time    = dicom_series.repetition_time,
            inversion_time     = dicom_series.inversion_time,
            slice_thickness    = dicom_series.slice_thickness,
            phase_encoding     = dicom_series.phase_encoding,
            number_of_files    = len(dicom_files),
            series_uid         = dicom_series.series_uid,
            modality           = dicom_series.modality,
        )

        # Populate the DICOM series ID.
        db.add(dicom_series)
        db.commit()

        for dicom_file in dicom_files:
            db.add(DbDicomArchiveFile(
                archive_id         = dicom_archive.id,
                series_number      = dicom_file.series_number,
                file_number        = dicom_file.file_number,
                echo_number        = dicom_file.echo_number,
                series_description = dicom_file.series_description,
                md5_sum            = dicom_file.md5_sum,
                file_name          = dicom_file.file_name,
                series_id          = dicom_series.id,
            ))

    db.commit()

from datetime import datetime
from sqlalchemy.orm import Session as Database
from lib.db.model.dicom_archive import DbDicomArchive
from lib.db.model.dicom_archive_file import DbDicomArchiveFile
from lib.db.model.dicom_archive_series import DbDicomArchiveSeries
from lib.db.query.dicom_archive import delete_dicom_archive_file_series, get_dicom_archive_series_with_file_info
from lib.dicom.summary_type import Summary
from lib.dicom.dicom_log import DicomArchiveLog
import lib.dicom.text
import lib.dicom.summary_write
import lib.dicom.dicom_log


def populate_dicom_archive(
    dicom_archive: DbDicomArchive,
    log: DicomArchiveLog,
    summary: Summary,
    archive_path: str,
    session_id: int | None,
):
    """
    Populate a DICOM archive with information from its DICOM archiving log and DICOM summary.

    :param dicom_archive: The DICOM archive ORM object to populate.
    :param log: The DICOM arching log object.
    :param summary: The DICOM summary object.
    :param session_id: The optional session ID associated with the DICOM archive.
    """

    dicom_archive.study_uid                = summary.info.study_uid
    dicom_archive.patient_id               = summary.info.patient.id
    dicom_archive.patient_name             = summary.info.patient.name
    dicom_archive.patient_birthdate        = summary.info.patient.birth_date
    dicom_archive.patient_sex              = summary.info.patient.sex
    dicom_archive.neuro_db_center_name     = None
    dicom_archive.center_name              = summary.info.institution or ''
    dicom_archive.last_update              = None
    dicom_archive.date_acquired            = summary.info.scan_date
    dicom_archive.date_last_archived       = datetime.now()
    dicom_archive.acquisition_count        = len(summary.acquis)
    dicom_archive.dicom_file_count         = len(summary.dicom_files)
    dicom_archive.non_dicom_file_count     = len(summary.other_files)
    dicom_archive.md5_sum_dicom_only       = log.tarball_md5_sum
    dicom_archive.md5_sum_archive          = log.archive_md5_sum
    dicom_archive.creating_user            = log.creator_name
    dicom_archive.sum_type_version         = log.summary_version
    dicom_archive.tar_type_version         = log.archive_version
    dicom_archive.source_location          = log.source_path
    dicom_archive.archive_location         = archive_path
    dicom_archive.scanner_manufacturer     = summary.info.scanner.manufacturer
    dicom_archive.scanner_model            = summary.info.scanner.model
    dicom_archive.scanner_serial_number    = summary.info.scanner.serial_number
    dicom_archive.scanner_software_version = summary.info.scanner.software_version
    dicom_archive.session_id               = session_id
    dicom_archive.upload_attempt           = 0
    dicom_archive.create_info              = lib.dicom.dicom_log.write_to_string(log)
    dicom_archive.acquisition_metadata     = lib.dicom.summary_write.write_to_string(summary)
    dicom_archive.date_sent                = None
    dicom_archive.pending_transfer         = 0


def insert(db: Database, log: DicomArchiveLog, summary: Summary):
    """
    Insert a DICOM archive into the database.

    :param db: The database.
    :param log: The archiving log of the DICOM archive.
    :param summary: The summary of the DICOM archive.
    """

    dicom_archive = DbDicomArchive()
    populate_dicom_archive(dicom_archive, log, summary, 'TODO', None)
    dicom_archive.date_first_archived = datetime.now()
    db.add(dicom_archive)
    insert_files_series(db, dicom_archive, summary)
    return dicom_archive


def insert_files_series(db: Database, dicom_archive: DbDicomArchive, summary: Summary):
    for acqui in summary.acquis:
        db.add(DbDicomArchiveSeries(
            archive_id         = dicom_archive.id,
            series_number      = acqui.series_number,
            series_description = acqui.series_description,
            sequence_name      = acqui.sequence_name,
            echo_time          = acqui.echo_time,
            repetition_time    = acqui.repetition_time,
            inversion_time     = acqui.inversion_time,
            slice_thickness    = acqui.slice_thickness,
            phase_encoding     = acqui.phase_encoding,
            number_of_files    = acqui.number_of_files,
            series_uid         = acqui.series_uid,
            modality           = acqui.modality,
        ))

    for file in summary.dicom_files:
        series = get_dicom_archive_series_with_file_info(
            db,
            file.series_uid or '',
            file.series_number or 1,
            file.echo_time,
            file.sequence_name or '',
        )

        db.add(DbDicomArchiveFile(
            archive_id         = dicom_archive.id,
            series_number      = file.series_number,
            file_number        = file.file_number,
            echo_number        = file.echo_number,
            series_description = file.series_description,
            md5_sum            = file.md5_sum,
            file_name          = file.file_name,
            series_id          = series.id,
        ))


def update(db: Database, dicom_archive: DbDicomArchive, log: DicomArchiveLog, summary: Summary):
    """
    Insert a DICOM archive into the database.

    :param db: The database.
    :param archive: The DICOM archive to update.
    :param log: The archiving log of the DICOM archive.
    :param summary: The summary of the DICOM archive.
    """

    # Delete the associated database DICOM files and series.
    delete_dicom_archive_file_series(db, dicom_archive)

    # Update the database record with the new DICOM information.
    populate_dicom_archive(dicom_archive, log, summary, 'TODO', None)

    # Insert the new DICOM files and series.
    insert_files_series(db, dicom_archive, summary)

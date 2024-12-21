from typing import Optional

from sqlalchemy import delete, select
from sqlalchemy.orm import Session as Database

from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.dicom_archive_file import DbDicomArchiveFile
from lib.db.models.dicom_archive_series import DbDicomArchiveSeries


def try_get_dicom_archive_with_study_uid(db: Database, study_uid: str):
    """
    Get a DICOM archive from the database using its study UID, or return `None` if no DICOM
    archive is found.
    """

    query = select(DbDicomArchive).where(DbDicomArchive.study_uid == study_uid)
    return db.execute(query).scalar_one_or_none()


def delete_dicom_archive_file_series(db: Database, dicom_archive: DbDicomArchive):
    """
    Delete from the database all the DICOM archive files and series associated with a DICOM
    archive.
    """

    db.execute(delete(DbDicomArchiveFile)
        .where(DbDicomArchiveFile.archive_id == dicom_archive.id))

    db.execute(delete(DbDicomArchiveSeries)
        .where(DbDicomArchiveSeries.archive_id == dicom_archive.id))


def get_dicom_archive_series_with_file_info(
    db: Database,
    series_uid: str,
    series_number: int,
    echo_time: Optional[float],
    sequence_name: Optional[str],
):
    """
    Get a DICOM archive series from the database using its file information, or raise an
    exception if no DICOM archive series is found.
    """

    query = select(DbDicomArchiveSeries) \
        .where(DbDicomArchiveSeries.series_uid    == series_uid) \
        .where(DbDicomArchiveSeries.series_number == series_number) \
        .where(DbDicomArchiveSeries.echo_time     == echo_time) \
        .where(DbDicomArchiveSeries.sequence_name == sequence_name)

    return db.execute(query).scalar_one()

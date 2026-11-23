from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_candidate_error import DbMriCandidateError


def try_get_matching_mri_candidate_error(
    db: Database,
    dicom_archive_id: int | None,
    series_uid: str | None,
    echo_time: float | None,
    patient_name: str | None,
    reason: str,
) -> DbMriCandidateError | None:
    """
    Get an MRI candidate error from the database using the provided information, or return
    `None` if no candidate error is found.
    """

    return db.execute(select(DbMriCandidateError)
        .where(DbMriCandidateError.dicom_archive_id == dicom_archive_id)
        .where(DbMriCandidateError.series_uid == series_uid)
        .where(DbMriCandidateError.echo_time == echo_time)
        .where(DbMriCandidateError.patient_name == patient_name)
        .where(DbMriCandidateError.reason == reason)
    ).scalars().first()

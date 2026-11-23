from datetime import datetime
from pathlib import Path

from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.mri_candidate_error import DbMriCandidateError
from lib.db.queries.mri_candidate_error import try_get_matching_mri_candidate_error
from lib.env import Env


def register_mri_candidate_error(
    env: Env,
    patient_name: str | None,
    dicom_archive: DbDicomArchive | None,
    file_path: Path,
    series_uid: str | None,
    echo_time: float | None,
    reason: str,
) -> DbMriCandidateError:
    """
    Register an MRI candidate error in the database using the provided information, or return
    the existing error if it already exists.
    """

    dicom_archive_id = dicom_archive.id if dicom_archive is not None else None

    error = try_get_matching_mri_candidate_error(
        env.db, dicom_archive_id, series_uid, echo_time, patient_name, reason,
    )

    if error is not None:
        return error

    error = DbMriCandidateError(
        time_run         = datetime.now(),
        dicom_archive_id = dicom_archive_id,
        file_path        = file_path,
        patient_name     = patient_name,
        reason           = reason,
        series_uid       = series_uid,
        echo_time        = echo_time,
    )

    env.db.add(error)
    env.db.flush()

    return error
